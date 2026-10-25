import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cuelink_config/config/client.dart';
import 'package:cuelink_config/config/models.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';

import 'config_test.dart' show Wire;

Json fixture() => jsonDecode(
  File('../../firmware/docs/configuration_vector.json').readAsStringSync(),
) as Json;
Json nearLimit() {
  final value = fixture();
  for (final b in value['buttons'] as List) {
    b['slots'] = [
      for (var i = 0; i < 4; i++)
        {
          'enabled': true,
          'protocol': 'udp',
          'udp': {
            'format': 'text',
            'payload': '',
            'lineEnding': 'none',
            'destinations': [
              {'ip': '192.0.2.42', 'port': 7000},
            ],
          },
        },
    ];
  }
  final overhead = utf8.encode(jsonEncode(value)).length;
  final size = min(1024, (maxConfigurationBytes - overhead) ~/ 16);
  for (final b in value['buttons'] as List) {
    for (final s in b['slots'] as List) {
      s['udp']['payload'] = 'X' * size;
    }
  }
  Configuration.parse(value);
  return value;
}

/// Independent v2 peripheral model: one request frame in flight, explicit MTU
/// negotiation, CRC/order checks, notifications emitted after ATT write completes,
/// authoritative scoped reads and persistence counted separately from transfers.
class FastWire implements FastConfigWire {
  FastWire({
    this.frameBytes = 182,
    this.latency = const Duration(milliseconds: 15),
    this.pairingDelay = Duration.zero,
    Json? config,
  }) : current = config ?? fixture();
  final int frameBytes;
  final Duration latency;
  final Duration pairingDelay;
  bool firstWrite = true;
  int readCalls = 0;
  Json current;
  final stream = StreamController<List<int>>.broadcast(sync: true);
  final timers = <Timer>[];
  final operations = <String>[];
  final input = <int>[];
  final seen = <int, String>{};
  List<int> snapshot = [], output = [];
  int rid = 0,
      length = 0,
      crc = 0,
      seq = 0,
      payload = 12,
      mutations = 0,
      inFlight = 0;
  int? dropOnce;
  bool duplicate = false, stale = false, dropAll = false, staleReads = false;
  bool wrongScope = false,
      badCrc = false,
      wrongVersion = false,
      offline = false;
  bool corruptValue = false, conflict = false, pending = false;
  bool subscriptionError = false;
  void Function(List<int>)? afterNotification;
  String? failPhase;
  @override
  Future<ConfigSession?> prepareConfig(String id) async {
    await Future<void>.delayed(latency * 2); // Modeled MTU/subscription setup.
    return ConfigSession(frameBytes, stream.stream);
  }

  @override
  Future<List<int>> readConfig(String id) async {
    readCalls++;
    if (offline) throw StateError('offline');
    await Future<void>.delayed(latency);
    return staleReads ? frame(0x80, rid + 1, 999, const [], 2) : snapshot;
  }

  void publish(List<int> response) {
    snapshot = response;
    if (dropAll || dropOnce == response[1]) {
      dropOnce = null;
      return;
    }
    timers.add(
      Timer(latency, () {
        if (offline) return;
        if (stale) stream.add(frame(response[1], rid + 1, 500, const [], 2));
        if (subscriptionError) {
          stream.addError(StateError('subscription failed'));
          return;
        }
        stream.add(response);
        afterNotification?.call(response);
        if (duplicate) {
          stream.add(response);
          timers.add(
            Timer(const Duration(milliseconds: 100), () {
              if (!offline) stream.add(response);
            }),
          );
        }
      }),
    );
  }

  @override
  Future<void> writeConfig(String id, List<int> bytes) async {
    expect(++inFlight, 1, reason: 'No concurrent writes');
    try {
      if (offline) throw StateError('offline');
      if (firstWrite) {
        firstWrite = false;
        await Future<void>.delayed(pairingDelay);
      }
      await Future<void>.delayed(latency);
      expect(bytes.length, lessThanOrEqualTo(frameBytes));
      expect(bytes[0], 2);
      final d = ByteData.sublistView(Uint8List.fromList(bytes));
      final kind = bytes[1],
          id = d.getUint32(2, Endian.little),
          index = d.getUint16(6, Endian.little);
      if (kind == 1) {
        rid = id;
        seq = 0;
        input.clear();
        length = d.getUint32(8, Endian.little);
        crc = d.getUint32(12, Endian.little);
        final chosen = min(frameBytes, d.getUint16(16, Endian.little));
        payload = chosen - 8;
        final response = frame(0x80, rid, 0, [
          chosen & 255,
          chosen >> 8,
        ], wrongVersion ? 1 : 2);
        publish(response);
      } else if (kind == 2) {
        if (failPhase == 'upload') {
          offline = true;
          throw StateError('link lost during upload');
        }
        expect(id, rid);
        expect(index, seq);
        input.addAll(bytes.sublist(8));
        seq++;
        publish(frame(0x80, rid, seq, const [], 2));
      } else if (kind == 3) {
        expect(input.length, length);
        expect(crc32(input), crc);
        final request = jsonDecode(utf8.decode(input)) as Json;
        final op = request['op'] as String;
        operations.add(op);
        Json response;
        if (op == 'query') {
          pending = false;
          response = {'ok': true, 'pending': false};
        } else if (op == 'read') {
          response = {
            'ok': true,
            'pending': pending,
            'revision': current['revision'],
            'configuration': current,
          };
        } else if (op == 'read_scope') {
          if (failPhase == 'verification') {
            offline = true;
            throw StateError('link lost during verification');
          }
          final scope = request['scope'];
          final value = scope == 'button'
              ? current['buttons'][request['button']]
              : current[scope];
          final copy = jsonDecode(jsonEncode(value));
          if (corruptValue && scope == 'button') copy['label'] = 'Wrong';
          response = {
            'ok': true,
            'pending': false,
            'revision': current['revision'],
            'scope': wrongScope ? 'network' : scope,
            'button': request['button'],
            'value': copy,
          };
        } else {
          final fingerprint = jsonEncode(request);
          if (seen.containsKey(rid)) {
            response = {
              'ok': seen[rid] == fingerprint,
              'revision': current['revision'],
            };
          } else if (conflict || request['revision'] != current['revision']) {
            response = {'ok': false, 'error': 'Revision conflict'};
          } else {
            final previous = op == 'button'
                ? current['buttons'][request['button']]
                : current[op];
            if (jsonEncode(previous) != jsonEncode(request['value'])) {
              if (op == 'button') {
                current['buttons'][request['button']] = request['value'];
              } else {
                current[op] = request['value'];
              }
              await Future<void>.delayed(
                const Duration(milliseconds: 40),
              ); // Modeled persistence.
              current['revision']++;
              mutations++;
            }
            seen[rid] = fingerprint;
            response = {
              'ok': true,
              'revision': current['revision'],
              'pending': false,
            };
          }
          if (failPhase == 'commit') {
            offline = true;
            throw StateError('link lost after persistence');
          }
        }
        output = utf8.encode(jsonEncode(response));
        publish(
          frame(
            0x81,
            rid,
            0,
            words(output.length, crc32(output) ^ (badCrc ? 1 : 0)),
            2,
          ),
        );
      } else if (kind == 5) {
        publish(
          frame(
            0x82,
            rid,
            index,
            output.skip(index * payload).take(payload).toList(),
            2,
          ),
        );
      } else if (kind == 4) {
        publish(frame(0x80, id, index, const [], 2));
      }
    } finally {
      inFlight--;
    }
  }

  void dispose() {
    for (final t in timers) {
      t.cancel();
    }
    unawaited(stream.close());
  }
}

Future<void> simulated(Future<void> Function(FakeAsync clock) run) async {
  final clock = FakeAsync();
  var done = false;
  Object? error;
  StackTrace? stack;
  clock.run((_) {
    run(clock).then(
      (_) => done = true,
      onError: (Object e, StackTrace s) {
        error = e;
        stack = s;
        done = true;
      },
    );
  });
  while (!done && clock.elapsed < const Duration(minutes: 2)) {
    clock.elapse(const Duration(milliseconds: 10));
    // Stream cancellation can complete through the SDK's cached root-zone
    // Future; let that microtask drain without assigning it simulated latency.
    await Future<void>.delayed(Duration.zero);
  }
  expect(done, true, reason: 'Simulation exceeded bounded deadline');
  if (error != null) Error.throwWithStackTrace(error!, stack!);
}

class LegacyCapWire extends Wire implements FastConfigWire {
  @override
  Future<ConfigSession?> prepareConfig(String id) async => null;
}

void main() {
  for (final budget in [20, 182, 244]) {
    test(
      'v2 MTU ${budget + 3}: near-limit load and scoped saves at 30ms round trip',
      () async {
        await simulated((clock) async {
          final config = nearLimit();
          final bytes = utf8.encode(jsonEncode(config)).length;
          expect(bytes, greaterThan(maxConfigurationBytes - 16));
          final wire = FastWire(frameBytes: budget, config: config),
              client = ConfigClient(FastWire(), 'unused');
          client.dispose();
          final c = ConfigClient(wire, 'device');
          final start = clock.elapsed;
          await c.load();
          final loadMs = (clock.elapsed - start).inMilliseconds;
          expect(c.configuration, isNotNull);
          expect(wire.operations, ['read']);
          expect(c.lastTiming['reads'] ?? 0, 0);
          final button = c.configuration!.buttons[0].toJson()
            ..['label'] = 'New name';
          final saveAt = clock.elapsed;
          expect(await c.save('button', button, button: 0), true);
          final saveMs = (clock.elapsed - saveAt).inMilliseconds;
          expect(wire.operations.sublist(1), ['button', 'read_scope']);
          expect(wire.mutations, 1);
          expect(c.configuration!.buttons[0].label, 'New name');
          expect(c.configuration!.buttons[1].toJson(), config['buttons'][1]);
          final routeAt = clock.elapsed;
          expect(await c.save('routing', Routing(true, []).toJson()), true);
          final routeMs = (clock.elapsed - routeAt).inMilliseconds;
          if (budget > 20) {
            expect(loadMs, lessThanOrEqualTo(5000));
            expect(saveMs, lessThanOrEqualTo(5000));
            expect(routeMs, lessThanOrEqualTo(5000));
          }
          debugPrint(
            'SIMULATED frame=$budget config=$bytes bytes load=${loadMs}ms button=${saveMs}ms routing=${routeMs}ms',
          );
          final writes = wire.mutations;
          expect(await c.save('button', button, button: 0), true);
          expect(await c.save('button', button, button: 0), true);
          expect(
            wire.mutations,
            writes,
            reason: 'No-op saves must not persist again',
          );
          c.dispose();
          wire.dispose();
        });
      },
    );
  }
  test('lost ACK/chunk notifications use bounded recovery reads; duplicate/stale/delayed frames ignored', () async {
    await simulated((clock) async {
      final wire = FastWire()
        ..duplicate = true
        ..stale = true
        ..dropOnce = 0x80;
      final c = ConfigClient(wire, 'device');
      await c.load();
      expect(c.configuration, isNotNull);
      expect(c.lastTiming['recoveryReads'], 1);
      wire.dropOnce = 0x82;
      final before = wire.operations.length;
      expect(await c.save('routing', Routing(true, []).toJson()), true);
      expect(c.lastTiming['recoveryReads'], 1);
      expect(
        wire.operations.sublist(before).where((op) => op == 'routing').length,
        1,
      );
      c.dispose();
      wire.dispose();
    });
  });
  test(
    'legacy capability fallback preserves v1 framing and full verification',
    () async {
      final wire = LegacyCapWire();
      final c = ConfigClient(wire, 'device');
      await c.load();
      expect(
        await c.save(
          'button',
          ButtonConfig('Legacy', true, []).toJson(),
          button: 0,
        ),
        true,
      );
      expect(wire.operations.map((o) => o['op']).toList(), [
        'read',
        'button',
        'read',
      ]);
      expect(c.lastTiming['protocol'], 1);
      c.dispose();
    },
  );
  test('initial system pairing may exceed five seconds without early recovery reads', () async {
    await simulated((clock) async {
      final wire = FastWire(pairingDelay: const Duration(seconds: 10));
      final c = ConfigClient(wire, 'device');
      await c.load();
      expect(c.configuration, isNotNull);
      expect(wire.readCalls, 0);
      expect(clock.elapsed.inSeconds, greaterThanOrEqualTo(10));
      c.dispose();
      wire.dispose();
    });
  });
  for (final config in [fixture(), nearLimit()]) {
    test('healthy MTU185 at 60ms round trip stays under five seconds', () async {
      await simulated((clock) async {
        final wire = FastWire(
          config: config,
          latency: const Duration(milliseconds: 30),
        );
        final c = ConfigClient(wire, 'device');
        final start = clock.elapsed;
        await c.load();
        final loadMs = (clock.elapsed - start).inMilliseconds;
        expect(c.configuration, isNotNull);
        final at = clock.elapsed;
        final button = c.configuration!.buttons[0].toJson()
          ..['label'] = 'Bench';
        expect(await c.save('button', button, button: 0), true);
        final saveMs = (clock.elapsed - at).inMilliseconds;
        expect(loadMs, lessThanOrEqualTo(5000));
        expect(saveMs, lessThanOrEqualTo(5000));
        debugPrint(
          'SIMULATED RTT=60 frame=182 config=${utf8.encode(jsonEncode(config)).length} load=${loadMs}ms button=${saveMs}ms',
        );
        c.dispose();
        wire.dispose();
      });
    });
  }
  test(
    'notification error fails safely without replaying a mutation',
    () async {
      await simulated((clock) async {
        final wire = FastWire();
        final c = ConfigClient(wire, 'device');
        await c.load();
        wire.subscriptionError = true;
        expect(await c.save('routing', Routing(true, []).toJson()), false);
        expect(c.uncertain, true);
        expect(wire.mutations, 0);
        c.dispose();
        wire.dispose();
      });
    },
  );
  test(
    'disconnect after last verification notification cannot publish cache',
    () async {
      await simulated((clock) async {
        final wire = FastWire();
        final c = ConfigClient(wire, 'device');
        await c.load();
        wire.afterNotification = (packet) {
          final seq = ByteData.sublistView(Uint8List.fromList(packet))
              .getUint16(6, Endian.little);
          if (packet[1] == 0x82 &&
              wire.operations.last == 'read_scope' &&
              seq == (wire.output.length - 1) ~/ wire.payload) {
            wire.afterNotification = null;
            c.disconnected();
          }
        };
        final value = c.configuration!.buttons[0].toJson()..['label'] = 'New';
        expect(await c.save('button', value, button: 0), false);
        expect(c.configuration!.revision, 0);
        expect(c.uncertain, true);
        expect(wire.mutations, 1);
        c.dispose();
        wire.dispose();
      });
    },
  );
  test(
    'cancel serializes the abort behind its upload frame and does not commit',
    () async {
      await simulated((clock) async {
        final wire = FastWire();
        final c = ConfigClient(wire, 'device');
        await c.load();
        Future<void>? cancelled;
        wire.afterNotification = (packet) {
          if (packet[1] == 0x80 && packet[6] == 1) {
            wire.afterNotification = null;
            cancelled = c.cancel();
          }
        };
        final value = c.configuration!.buttons[0].toJson()..['label'] = 'New';
        expect(await c.save('button', value, button: 0), false);
        await cancelled;
        expect(wire.mutations, 0);
        expect(c.uncertain, true);
        expect(c.configuration!.revision, 0);
        c.dispose();
        wire.dispose();
      });
    },
  );
  for (final phase in ['upload', 'commit', 'verification']) {
    test(
      'disconnect during $phase preserves cache and never replays save',
      () async {
        await simulated((clock) async {
          final wire = FastWire(), c = ConfigClient(FastWire(), 'unused');
          c.dispose();
          final client = ConfigClient(wire, 'device');
          await client.load();
          wire.failPhase = phase;
          final value = client.configuration!.buttons[0].toJson()
            ..['label'] = 'Saved';
          expect(await client.save('button', value, button: 0), false);
          expect(client.configuration!.revision, 0);
          expect(client.uncertain, true);
          final mutations = wire.mutations;
          expect(await client.save('button', value, button: 0), false);
          expect(wire.mutations, mutations);
          wire.offline = false;
          wire.failPhase = null;
          await client.load();
          expect(client.uncertain, false);
          expect(wire.mutations, phase == 'upload' ? 0 : 1);
          client.dispose();
          wire.dispose();
        });
      },
    );
  }
  for (final fault in [
    'crc',
    'scope',
    'value',
    'revision',
    'version',
    'missing',
  ]) {
    test(
      '$fault faults never publish unverified cache or replay mutations',
      () async {
        await simulated((clock) async {
          final wire = FastWire();
          final c = ConfigClient(wire, 'device');
          await c.load();
          final before = jsonEncode(c.configuration!.toJson());
          if (fault == 'crc') wire.badCrc = true;
          if (fault == 'scope') wire.wrongScope = true;
          if (fault == 'value') wire.corruptValue = true;
          if (fault == 'revision') wire.conflict = true;
          if (fault == 'version') wire.wrongVersion = true;
          if (fault == 'missing') {
            wire.dropAll = true;
            wire.staleReads = true;
          }
          final value = c.configuration!.buttons[0].toJson()
            ..['label'] = 'Changed';
          expect(await c.save('button', value, button: 0), false);
          expect(jsonEncode(c.configuration!.toJson()), before);
          expect(c.uncertain, true);
          expect(
            wire.operations.where((o) => o == 'button').length,
            lessThanOrEqualTo(1),
          );
          c.dispose();
          wire.dispose();
        });
      },
    );
  }
  test('load recovers a pending network transaction then performs authoritative full refresh', () async {
    await simulated((clock) async {
      final wire = FastWire()..pending = true;
      final c = ConfigClient(wire, 'device');
      await c.load();
      expect(wire.operations, ['read', 'query', 'read']);
      expect(c.configuration, isNotNull);
      c.dispose();
      wire.dispose();
    });
  });
}
