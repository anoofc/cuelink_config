import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'models.dart';

abstract class ConfigWire {
  Future<void> writeConfig(String id, List<int> bytes);
  Future<List<int>> readConfig(String id);
}

/// Only peers advertising capability bit 7 may use v2 framing/scoped readback.
class ConfigSession {
  ConfigSession(this.frameBytes, this.responses);
  final int frameBytes;
  final Stream<List<int>> responses;
}

abstract class FastConfigWire implements ConfigWire {
  Future<ConfigSession?> prepareConfig(String id);
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

List<int> frame(
  int kind,
  int id,
  int sequence, [
  List<int> body = const [],
  int version = 1,
]) {
  final bytes = Uint8List(8 + body.length);
  final data = ByteData.sublistView(bytes);
  bytes[0] = version;
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
  int? _operationEpoch;
  int? lastRequest;
  Json? receipt;
  ConfigSession? _session;
  bool _responseFailed = false;
  Future<void> _writeTail = Future<void>.value();
  Future<void> _writeBytes(List<int> value) {
    final write = _writeTail.then(
      (_) => wire.writeConfig(id, value).timeout(const Duration(seconds: 60)),
    );
    _writeTail = write.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return write;
  }

  StreamSubscription<List<int>>? _responses;
  Future<void> _closeResponses() async {
    final subscription = _responses;
    _responses = null;
    try {
      await subscription?.cancel().timeout(const Duration(seconds: 3));
    } catch (_) {
      _count('cleanupFailures');
    }
  }

  Completer<List<int>>? _notificationWait;
  void Function(List<int>)? _responseHandler;
  Map<String, int> lastTiming = {};
  final Map<String, int> _counts = {};
  void _count(String key, [int n = 1]) =>
      _counts[key] = (_counts[key] ?? 0) + n;
  void _interrupt() {
    final wait = _notificationWait;
    if (wait != null && !wait.isCompleted) {
      wait.completeError(StateError('Session interrupted; reload settings.'));
    }
  }

  void emit() {
    if (!_disposed) notifyListeners();
  }

  void disconnected() {
    ++_epoch;
    _interrupt();
    uncertain = true;
    state = 'Disconnected / outcome unknown. Reconnect, then load authoritative settings before retrying.';
    emit();
  }

  Future<Json> _exchange(Json request) async {
    final epoch = _operationEpoch ?? _epoch;
    final requestId = Random.secure().nextInt(0xfffffffe) + 1;
    lastRequest = requestId;
    final bytes = utf8.encode(jsonEncode(request));
    if (bytes.isEmpty || bytes.length > maxConfigBytes) {
      invalid('Request exceeds 16384 bytes.');
    }
    final started = DateTime.now();
    void current() {
      if (epoch != _epoch || _disposed || _responseFailed) {
        throw StateError('Disconnected / outcome unknown.');
      }
      if (DateTime.now().difference(started) > const Duration(minutes: 3)) {
        throw TimeoutException('Configuration transfer timed out.');
      }
    }

    final version = _session == null ? 1 : 2;
    var payload = 12;
    List<int>? inspect(List<int> value, int kind, int sequence) {
      current();
      if (value.length < 8) return null;
      final d = ByteData.sublistView(Uint8List.fromList(value));
      final matching = d.getUint32(2, Endian.little) == requestId;
      if (value[1] == 0x84 &&
          (matching || d.getUint32(2, Endian.little) == 0)) {
        throw StateError(
          'Physical authorization required: press B3 on App connection.',
        );
      }
      if (!matching) return null;
      if (value[0] != version) {
        invalid(
          'Configuration protocol version mismatch. Reconnect and update firmware.',
        );
      }
      if (value[1] == 0x83) {
        throw StateError('Transfer rejected, cancelled or timed out.');
      }
      if (value[1] == kind &&
          ((version == 1 && kind == 0x81) ||
              d.getUint16(6, Endian.little) == sequence)) {
        return value;
      }
      return null;
    }

    Future<List<int>> read() async {
      _count('reads');
      return wire.readConfig(id).timeout(const Duration(seconds: 3));
    }

    Future<void> send(List<int> value) async {
      current();
      _count('writes');
      await _writeBytes(value);
      current();
    }

    Future<List<int>> exchangeFrame(
      List<int> value,
      int kind,
      int sequence,
    ) async {
      if (_session == null) {
        await send(value);
        for (var attempt = 0; attempt < 150; attempt++) {
          final result = inspect(await read(), kind, sequence);
          if (result != null) return result;
          _count('retries');
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        throw TimeoutException('No application acknowledgment.');
      }
      final completion = Completer<List<int>>();
      _notificationWait = completion;
      _responseHandler = (value) {
        if (completion.isCompleted) return;
        try {
          final result = inspect(value, kind, sequence);
          if (result != null) completion.complete(result);
        } catch (error, stack) {
          completion.completeError(error, stack);
        }
      };
      Future<List<int>> receive() async {
        // Never resend upload/commit frames: a missing notification is recovered
        // from the readable response snapshot, not by replaying a mutation.
        for (var attempt = 0; attempt < 3; attempt++) {
          try {
            return await completion.future.timeout(
              const Duration(milliseconds: 300),
            );
          } on TimeoutException {
            current();
            if (attempt == 2) break;
            _count('retries');
            _count('recoveryReads');
            _responseHandler?.call(await read());
          }
        }
        throw TimeoutException(
          'Configuration response missing; reload to resolve outcome.',
        );
      }

      // Attach an error sink immediately: a notification/disconnect can arrive
      // before ATT write completion (including the first system pairing dialog).
      unawaited(
        completion.future.then<void>(
          (_) {},
          onError: (Object _, StackTrace _) {},
        ),
      );
      try {
        await send(value);
        return await receive();
      } finally {
        _responseHandler = null;
        _notificationWait = null;
      }
    }

    List<int> packet(int kind, int seq, [List<int> body = const []]) =>
        frame(kind, requestId, seq, body, version);
    final requestedFrame = _session?.frameBytes ?? 20;
    _counts['frameBytes'] = requestedFrame;
    _counts['protocol'] = version;
    final startBody = [
      ...words(bytes.length, crc32(bytes)),
      if (version == 2) ...[requestedFrame & 255, requestedFrame >> 8],
    ];
    _count('uploadBytes', bytes.length);
    final ack = await exchangeFrame(packet(1, 0, startBody), 0x80, 0);
    if (version == 2) {
      if (ack.length != 10) invalid('Invalid v2 negotiation acknowledgment.');
      final chosen = ack[8] | (ack[9] << 8);
      if (chosen < 20 || chosen > requestedFrame || chosen > 244) {
        invalid('Unsafe negotiated frame size.');
      }
      _counts['frameBytes'] = chosen;
      payload = chosen - 8;
    }
    var sequence = 0;
    for (var offset = 0; offset < bytes.length; offset += payload) {
      _count('uploadChunks');
      await exchangeFrame(
        packet(
          2,
          sequence,
          bytes.sublist(offset, min(offset + payload, bytes.length)),
        ),
        0x80,
        sequence + 1,
      );
      ++sequence;
    }
    final meta = await exchangeFrame(packet(3, sequence), 0x81, 0);
    if (meta.length != 16) invalid('Invalid response manifest.');
    final d = ByteData.sublistView(Uint8List.fromList(meta));
    final length = d.getUint32(8, Endian.little),
        crc = d.getUint32(12, Endian.little);
    if (length < 1 || length > maxConfigBytes) {
      invalid('Invalid response length.');
    }
    final result = <int>[];
    for (var s = 0; result.length < length; ++s) {
      _count('downloadChunks');
      final chunk = await exchangeFrame(packet(5, s), 0x82, s);
      if (chunk.length != 8 + min(payload, length - result.length)) {
        invalid('Invalid response chunk.');
      }
      result.addAll(chunk.sublist(8));
    }
    _count('downloadBytes', result.length);
    if (crc32(result) != crc) {
      invalid('Configuration response integrity failed.');
    }
    current();
    final decoded = jsonDecode(utf8.decode(result));
    if (decoded is! Json) invalid('Invalid response.');
    return decoded;
  }

  Future<T?> operation<T>(String label, Future<T> Function() action) async {
    if (busy) return null;
    final timer = Stopwatch()..start();
    _counts
      ..clear()
      ..addAll({
        'writes': 0,
        'reads': 0,
        'notifications': 0,
        'recoveryReads': 0,
        'retries': 0,
        'uploadBytes': 0,
        'downloadBytes': 0,
        'uploadChunks': 0,
        'downloadChunks': 0,
      });
    _responseFailed = false;
    _operationEpoch = _epoch;
    busy = true;
    state = label;
    emit();
    try {
      if (wire is FastConfigWire) {
        _session = await (wire as FastConfigWire).prepareConfig(id);
        if (_session != null) {
          _responses = _session!.responses.listen(
            (value) {
              _count('notifications');
              _responseHandler?.call(value);
            },
            onError: (Object error) {
              _responseFailed = true;
              _interrupt();
            },
            onDone: () {
              _responseFailed = true;
              _interrupt();
            },
          );
        }
      }
      return await action();
    } catch (error) {
      uncertain = true;
      if (error is FormatException) {
        state = 'Failed: ${error.message}';
      } else if (error is StateError &&
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
      await _closeResponses();
      _session = null;
      timer.stop();
      lastTiming = {..._counts, 'elapsedMs': timer.elapsedMilliseconds};
      debugPrint('[ConfigTiming] $label $lastTiming');
      _operationEpoch = null;
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
      var response = await checked({'schema': 1, 'op': 'read'});
      if (response['pending'] == true) {
        await finish(response);
        response = await checked({'schema': 1, 'op': 'read'});
      }
      if (_operationEpoch != _epoch || _disposed || _responseFailed) {
        throw StateError('Session interrupted.');
      }
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
      final scoped = _session != null;
      final verified = await checked(
        scoped
            ? {'schema': 1, 'op': 'read_scope', 'scope': op, 'button': ?button}
            : {'schema': 1, 'op': 'read'},
      );
      if (verified['revision'] != savedRevision ||
          verified['pending'] == true) {
        invalid('Revision changed before readback; reload.');
      }
      if (scoped &&
          (verified['scope'] != op ||
              (op == 'button' && verified['button'] != button))) {
        invalid('Incorrect readback scope.');
      }
      final authoritative = scoped
          ? null
          : Configuration.parse(verified['configuration']);
      final actual = scoped
          ? switch (op) {
              'button' => ButtonConfig.parse(verified['value']).toJson(),
              'routing' => Routing.parse(verified['value']).toJson(),
              _ => NetworkConfig.parse(verified['value']).toJson(),
            }
          : switch (op) {
              'button' => authoritative!.buttons[button!].toJson(),
              'routing' => authoritative!.routing.toJson(),
              _ => authoritative!.network.toJson(),
            };
      final desired = switch (op) {
        'button' => ButtonConfig.parse(value).toJson(),
        'routing' => Routing.parse(value).toJson(),
        _ => NetworkConfig.parse(value).toJson(),
      };
      if (op == 'network') {
        desired['passwordConfigured'] = credential?['mode'] == 'replace'
            ? true
            : credential?['mode'] == 'open'
            ? false
            : configuration!.network.passwordConfigured;
      }
      if (jsonEncode(actual) != jsonEncode(desired)) {
        invalid('Readback differs; reload before retry.');
      }
      if (_operationEpoch != _epoch || _disposed || _responseFailed) {
        throw StateError('Session interrupted.');
      }
      if (scoped) {
        final updated = configuration!.toJson();
        updated['revision'] = savedRevision;
        if (op == 'button') {
          (updated['buttons'] as List)[button!] = actual;
        } else {
          updated[op] = actual;
        }
        configuration = Configuration.parse(updated);
      } else {
        configuration = authoritative;
      }
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
    _interrupt();
    uncertain = true;
    state = 'Cancelled / outcome unknown. Query device before retrying.';
    emit();
    if (request != null) {
      try {
        await _writeBytes(
          frame(4, request, 0, const [], _session == null ? 1 : 2),
        );
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _interrupt();
    unawaited(_closeResponses());
    _disposed = true;
    ++_epoch;
    super.dispose();
  }
}
