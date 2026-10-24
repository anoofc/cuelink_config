import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cuelink_config/config/models.dart';
import 'package:cuelink_config/config/client.dart';

Json vector() => jsonDecode(
  File('../../firmware/docs/configuration_vector.json').readAsStringSync(),
) as Json;

class Wire implements ConfigWire {
  Json current = vector();
  bool fail = false, disconnect = false, badCrc = false;
  int writes = 0;
  int request = 0;
  int sequence = 0;
  int length = 0;
  int crc = 0;
  final List<int> input = [];
  List<int> response = [];
  List<int> output = [];
  final List<Json> operations = [];
  @override
  Future<List<int>> readConfig(String id) async {
    if (disconnect) throw StateError('offline');
    return response;
  }

  @override
  Future<void> writeConfig(String id, List<int> bytes) async {
    if (disconnect) throw StateError('offline');
    expect(bytes.length, lessThanOrEqualTo(20));
    final d = ByteData.sublistView(Uint8List.fromList(bytes));
    final kind = bytes[1],
        rid = d.getUint32(2, Endian.little),
        seq = d.getUint16(6, Endian.little);
    if (kind == 1) {
      request = rid;
      sequence = 0;
      input.clear();
      length = d.getUint32(8, Endian.little);
      crc = d.getUint32(12, Endian.little);
      response = frame(0x80, request, 0);
    }
    if (kind == 2) {
      expect(rid, request);
      expect(seq, sequence);
      input.addAll(bytes.sublist(8));
      ++sequence;
      response = frame(0x80, request, sequence);
    }
    if (kind == 3) {
      expect(input.length, length);
      expect(crc32(input), crc);
      final op = jsonDecode(utf8.decode(input)) as Json;
      operations.add(op);
      Json reply;
      if (fail) {
        reply = {'ok': false, 'error': 'Revision conflict'};
      } else {
        if (op['op'] == 'button') {
          current['buttons'][op['button']] = op['value'];
          ++writes;
          current['revision']++;
        }
        if (op['op'] == 'routing') {
          current['routing'] = op['value'];
          ++writes;
          current['revision']++;
        }
        reply = {
          'ok': true,
          'pending': false,
          'revision': current['revision'],
          'configuration': current,
        };
      }
      output = utf8.encode(jsonEncode(reply));
      response = frame(
        0x81,
        request,
        seq,
        words(output.length, crc32(output) ^ (badCrc ? 1 : 0)),
      );
    }
    if (kind == 5) {
      response = frame(
        0x82,
        request,
        seq,
        output.skip(seq * 12).take(12).toList(),
      );
    }
    if (kind == 4) response = frame(0x80, rid, seq);
  }
}

void main() {
  test(
    'UTF-8 SSIDs preserve existing hotspot names and enforce byte limits',
    () {
      final value = vector();
      value['network']['ssid'] = 'Phone’s hotspot';
      expect(Configuration.parse(value).network.ssid, 'Phone’s hotspot');
      value['network']['ssid'] = '😀' * 9;
      expect(() => Configuration.parse(value), throwsFormatException);
      value['network']['ssid'] = 'bad\u0000ssid';
      expect(() => Configuration.parse(value), throwsFormatException);
    },
  );

  test('Dart and firmware share exact serialization vector and disabled slot bytes', () {
    final raw = File('../../firmware/docs/configuration_vector.json')
        .readAsStringSync()
        .trim();
    final config = Configuration.parse(jsonDecode(raw));
    expect(jsonEncode(config.toJson()), raw);
    expect(config.buttons[0].label, 'Main cue');
    expect(config.buttons[1].enabled, false);
    final udp = config.buttons[0].slots[1] as UdpTrigger;
    expect(udp.enabled, false);
    expect(udp.bytes, [65, 0, 66, 10, 255]);
    expect(() => udp.representation('text'), throwsFormatException);
  });
  test('four-slot and protocol/range validation', () {
    final raw = vector();
    final slots = raw['buttons'][0]['slots'] as List;
    slots.add(slots.first);
    expect(() => Configuration.parse(raw), returnsNormally);
    slots.add(slots.first);
    expect(() => Configuration.parse(raw), throwsFormatException);
    final bad = vector();
    bad['buttons'][0]['slots'][2]['midi']['channel'] = 17;
    expect(() => Configuration.parse(bad), throwsFormatException);
    final mixed = vector();
    mixed['buttons'][0]['slots'][0]['udp'] = {};
    expect(() => Configuration.parse(mixed), throwsFormatException);
    final unknown = vector();
    unknown['schema'] = 2;
    expect(() => Configuration.parse(unknown), throwsFormatException);
  });
  test('UDP representation and explicit line endings preserve exact bytes', () {
    final t = UdpTrigger(true, 'text', 'Go', 'crlf', []);
    final h = t.representation('hex');
    expect(h.payload, '476f0d0a');
    expect(h.lineEnding, 'none');
    expect(h.representation('text').bytes, t.bytes);
    expect(
      () => UdpTrigger.parse({
        'enabled': true,
        'udp': {
          'format': 'hex',
          'payload': 'a',
          'lineEnding': 'none',
          'destinations': [],
        },
      }),
      throwsFormatException,
    );
  });
  test('static addressing validation and zero-based program range', () {
    final raw = vector();
    raw['network'] = {
      'ssid': 'Test',
      'passwordConfigured': false,
      'dhcp': false,
      'ip': '192.168.1.10',
      'subnet': '255.255.255.0',
      'gateway': '192.168.1.1',
      'dns1': '0.0.0.0',
      'dns2': '0.0.0.0',
    };
    expect(() => Configuration.parse(raw), returnsNormally);
    raw['network']['gateway'] = '192.168.2.1';
    expect(() => Configuration.parse(raw), throwsFormatException);
    expect(
      MidiTrigger.parse({
        'enabled': true,
        'midi': {'type': 'program', 'channel': 16, 'program': 127},
      }).program,
      127,
    );
    expect(
      () => MidiTrigger.parse({
        'enabled': true,
        'midi': {'type': 'program', 'channel': 1, 'program': 128},
      }),
      throwsFormatException,
    );
  });
  test(
    'default-MTU framing, request IDs, integrity and saved revision readback',
    () async {
      final w = Wire(), client = ConfigClient(Wire(), 'unused');
      client.dispose();
      final c = ConfigClient(w, 'device');
      await c.load();
      expect(c.configuration!.revision, 0);
      final button = ButtonConfig('New label', false, []);
      expect(await c.save('button', button.toJson(), button: 1), true);
      expect(w.writes, 1);
      expect(c.configuration!.revision, 1);
      expect(c.state, contains('Saved and verified'));
      expect(w.operations.last['op'], 'read');
      expect(w.operations.where((r) => r['op'] == 'button').length, 1);
      c.dispose();
    },
  );
  test('uncertain/disconnected outcome requires explicit query, never retries save', () async {
    final w = Wire(), c = ConfigClient(Wire(), 'unused');
    c.dispose();
    final client = ConfigClient(w, 'device');
    await client.load();
    w.disconnect = true;
    expect(await client.save('routing', Routing(true, []).toJson()), false);
    expect(client.uncertain, true);
    expect(await client.save('routing', Routing(false, []).toJson()), false);
    expect(w.writes, 0);
    w.disconnect = false;
    await client.load();
    expect(client.uncertain, false);
    expect(w.operations.where((o) => o['op'] == 'routing'), isEmpty);
    client.dispose();
  });
  test('device rejection and response corruption never show Saved', () async {
    final w = Wire(), c = ConfigClient(Wire(), 'unused');
    c.dispose();
    final client = ConfigClient(w, 'device');
    await client.load();
    w.fail = true;
    expect(await client.save('routing', Routing(true, []).toJson()), false);
    expect(client.state, contains('Revision conflict'));
    expect(w.writes, 0);
    w.fail = false;
    w.badCrc = true;
    await client.load();
    expect(client.uncertain, true);
    expect(client.state, isNot(contains('Saved')));
    client.dispose();
  });
}
