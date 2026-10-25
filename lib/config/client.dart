import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'models.dart';

abstract class ConfigWire {
  Future<void> writeConfig(String id, List<int> bytes);
  Future<List<int>> readConfig(String id);
}

int crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final n in bytes) {
    crc ^= n;
    for (int b = 0; b < 8; ++b) {
      crc = (crc >> 1) ^ ((crc & 1) != 0 ? 0xedb88320 : 0);
    }
  }
  return (~crc) & 0xffffffff;
}

List<int> frame(int kind, int id, int sequence, [List<int> body = const []]) {
  final bytes = Uint8List(8 + body.length);
  final data = ByteData.sublistView(bytes);
  bytes[0] = 1;
  bytes[1] = kind;
  data.setUint32(2, id, Endian.little);
  data.setUint16(6, sequence, Endian.little);
  bytes.setRange(8, bytes.length, body);
  return bytes;
}

List<int> words(int length, int crc) {
  final bytes = Uint8List(8);
  final d = ByteData.sublistView(bytes);
  d.setUint32(0, length, Endian.little);
  d.setUint32(4, crc, Endian.little);
  return bytes;
}

class ConfigClient extends ChangeNotifier {
  ConfigClient(this.wire, this.id);
  final ConfigWire wire;
  final String id;
  Configuration? configuration;
  String state = 'Load settings to begin.';
  bool busy = false, uncertain = false, _disposed = false;
  int _epoch = 0;
  int? lastRequest;
  Json? receipt;
  void emit() {
    if (!_disposed) notifyListeners();
  }

  void disconnected() {
    ++_epoch;
    uncertain = true;
    state = 'Disconnected / outcome unknown. Reconnect, then load authoritative settings before retrying.';
    emit();
  }

  Future<Json> _exchange(Json request) async {
    final epoch = _epoch;
    final requestId = Random.secure().nextInt(0xfffffffe) + 1;
    lastRequest = requestId;
    final bytes = utf8.encode(jsonEncode(request));
    if (bytes.isEmpty || bytes.length > maxConfigBytes) {
      invalid('Request exceeds 16384 bytes.');
    }
    final started = DateTime.now();
    void current() {
      if (epoch != _epoch || _disposed) {
        throw StateError('Disconnected / outcome unknown.');
      }
      if (DateTime.now().difference(started) > const Duration(minutes: 3)) {
        throw TimeoutException('Configuration transfer timed out.');
      }
    }

    Future<List<int>> waitFor(int kind, int sequence) async {
      final until = DateTime.now().add(const Duration(seconds: 15));
      while (true) {
        current();
        final value = await wire
            .readConfig(id)
            .timeout(const Duration(seconds: 60));
        current();
        if (value.length >= 8 && value[0] == 1) {
          final d = ByteData.sublistView(Uint8List.fromList(value));
          final matching = d.getUint32(2, Endian.little) == requestId;
          if (value[1] == 0x84) {
            throw StateError(
              'Physical authorization required: press B3 on App connection.',
            );
          }
          if (matching && value[1] == 0x83) {
            throw StateError('Transfer rejected, cancelled or timed out.');
          }
          if (matching &&
              value[1] == kind &&
              (kind == 0x81 || d.getUint16(6, Endian.little) == sequence)) {
            return value;
          }
        }
        if (DateTime.now().isAfter(until)) {
          throw TimeoutException('No application acknowledgment.');
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }

    Future<void> send(List<int> value) async {
      current();
      await wire.writeConfig(id, value).timeout(const Duration(seconds: 60));
      current();
    }

    await send(frame(1, requestId, 0, words(bytes.length, crc32(bytes))));
    await waitFor(0x80, 0);
    var sequence = 0;
    for (var offset = 0; offset < bytes.length; offset += 12) {
      await send(
        frame(
          2,
          requestId,
          sequence,
          bytes.sublist(offset, min(offset + 12, bytes.length)),
        ),
      );
      ++sequence;
      await waitFor(0x80, sequence);
    }
    await send(frame(3, requestId, sequence));
    final meta = await waitFor(0x81, sequence);
    if (meta.length != 16) invalid('Invalid response manifest.');
    final d = ByteData.sublistView(Uint8List.fromList(meta));
    final length = d.getUint32(8, Endian.little),
        crc = d.getUint32(12, Endian.little);
    if (length < 1 || length > maxConfigBytes) {
      invalid('Invalid response length.');
    }
    final result = <int>[];
    for (var s = 0; result.length < length; ++s) {
      await send(frame(5, requestId, s));
      final chunk = await waitFor(0x82, s);
      if (chunk.length != 8 + min(12, length - result.length)) {
        invalid('Invalid response chunk.');
      }
      result.addAll(chunk.sublist(8));
    }
    if (crc32(result) != crc) {
      invalid('Configuration response integrity failed.');
    }
    final decoded = jsonDecode(utf8.decode(result));
    if (decoded is! Json) invalid('Invalid response.');
    return decoded;
  }

  Future<T?> operation<T>(String label, Future<T> Function() action) async {
    if (busy) return null;
    busy = true;
    state = label;
    emit();
    try {
      return await action();
    } catch (error) {
      uncertain = true;
      if (error is StateError &&
          error.message.toString().startsWith(
            'Physical authorization required',
          )) {
        state = 'Failed: ${error.message}';
      } else if (!state.startsWith('Failed:') &&
          !state.startsWith('Disconnected') &&
          !state.startsWith('Cancelled')) {
        state = 'Failed or outcome unknown. Load from device to query the result before retrying.';
      }
      return null;
    } finally {
      busy = false;
      emit();
    }
  }

  Future<Json> checked(Json value) async {
    final r = await _exchange(value);
    if (r['ok'] != true) {
      state = 'Failed: ${r['error'] ?? 'Device rejected operation'}';
      emit();
      throw StateError('Device rejected operation.');
    }
    return r;
  }

  Future<Json> finish(Json result, {String waiting = 'Testing network'}) async {
    final until = DateTime.now().add(const Duration(seconds: 40));
    while (result['pending'] == true) {
      state = '$waiting / waiting for controller';
      emit();
      if (DateTime.now().isAfter(until)) {
        throw TimeoutException('Controller transaction still pending.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
      result = await checked({'schema': 1, 'op': 'query'});
    }
    return result;
  }

  Future<void> load() async {
    await operation('Loading settings…', () async {
      await wire.readConfig(id).timeout(const Duration(seconds: 60));
      var outcome = await _exchange({'schema': 1, 'op': 'query'});
      final deadline = DateTime.now().add(const Duration(seconds: 40));
      while (outcome['pending'] == true) {
        if (DateTime.now().isAfter(deadline)) {
          throw TimeoutException('Network operation pending.');
        }
        await Future<void>.delayed(const Duration(milliseconds: 400));
        outcome = await _exchange({'schema': 1, 'op': 'query'});
      }
      final response = await checked({'schema': 1, 'op': 'read'});
      configuration = Configuration.parse(response['configuration']);
      receipt = response;
      uncertain = false;
      state = 'Connected · Settings loaded';
    });
  }

  Future<bool> save(
    String op,
    Json value, {
    int? button,
    Json? credential,
    int? revision,
  }) async {
    if (configuration == null || uncertain) return false;
    final result = await operation('Sending configuration', () async {
      final expected = revision ?? configuration!.revision;
      final r = await finish(
        await checked({
          'schema': 1,
          'op': op,
          'revision': expected,
          'button': ?button,
          'value': value,
          'credential': ?credential,
        }),
      );
      final savedRevision = r['revision'];
      if (savedRevision is! int) invalid('Missing saved revision.');
      final verified = await checked({'schema': 1, 'op': 'read'});
      final authoritative = Configuration.parse(verified['configuration']);
      if (authoritative.revision != savedRevision) {
        invalid('Revision changed before readback; reload.');
      }
      final actual = switch (op) {
        'button' => authoritative.buttons[button!].toJson(),
        'routing' => authoritative.routing.toJson(),
        _ => authoritative.network.toJson(),
      };
      final desired = switch (op) {
        'button' => ButtonConfig.parse(value).toJson(),
        'routing' => Routing.parse(value).toJson(),
        _ => NetworkConfig.parse(value).toJson(),
      };
      if (op == 'network') {
        desired['passwordConfigured'] = actual['passwordConfigured'];
      }
      if (jsonEncode(actual) != jsonEncode(desired)) {
        invalid('Readback differs; reload before retry.');
      }
      configuration = authoritative;
      receipt = verified;
      state = 'Saved and verified';
      uncertain = false;
      return true;
    });
    return result ?? false;
  }

  Future<List<Json>?> scan() async =>
      operation('Scanning Wi-Fi on the controller', () async {
        final r = await finish(await checked({'schema': 1, 'op': 'scan'}));
        state = 'Controller scan complete';
        return (r['networks'] as List).cast<Json>();
      });
  Future<void> cancel() async {
    final request = lastRequest;
    ++_epoch;
    uncertain = true;
    state = 'Cancelled / outcome unknown. Query device before retrying.';
    emit();
    if (request != null) {
      try {
        await wire
            .writeConfig(id, frame(4, request, 0))
            .timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_epoch;
    super.dispose();
  }
}
