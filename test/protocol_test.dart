import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cuelink_config/ble/protocol.dart';

void main() {
  final vectors =
      (jsonDecode(
        File('../../firmware/docs/ble_protocol_vectors.json')
            .readAsStringSync(),
      ) as Map<String, dynamic>).map(
        (key, value) => MapEntry(key, List<int>.from(value as List)),
      );

  test(
    'firmware golden information: identity, version, capability byte order',
    () {
      final info = DeviceInformation.decode(vectors['information']!);
      expect(info.identifier, '021122334455');
      expect(info.firmware, '0.5.0');
      expect(info.capabilities, 255);
      final futureCapabilities = [...vectors['information']!]..[11] = 128;
      expect(DeviceInformation.decode(futureCapabilities).capabilities, 0x80ff);
    },
  );
  test('firmware golden status: network-order IP, signed RSSI, little-endian uptime', () {
    final status = LiveStatus.decode(vectors['connected']!);
    expect(status.wifi, WifiState.connected);
    expect(status.ipv4, '192.0.2.1');
    expect(status.rssi, -52);
    expect(status.uptimeSeconds, 0x01020304);
    expect(status.diagnostics, false);
  });
  test(
    'disconnected values are unavailable, including maximum unsigned uptime',
    () {
      final status = LiveStatus.decode(vectors['disconnected']!);
      expect(status.wifi, WifiState.reconnecting);
      expect(status.ipv4, isNull);
      expect(status.rssi, isNull);
      expect(status.uptimeSeconds, 0xffffffff);
      expect(status.diagnostics, true);
      for (final state in [0, 1, 3]) {
        expect(
          LiveStatus.decode([...vectors['disconnected']!]..[1] = state).ipv4,
          isNull,
        );
      }
    },
  );
  test('malformed length and byte values are rejected by both decoders', () {
    for (final payload in <List<int>>[
      [],
      [1],
      List.filled(11, 1),
      List.filled(13, 1),
      [...vectors['connected']!]..[2] = -1,
      [...vectors['connected']!]..[2] = 256,
    ]) {
      expect(() => LiveStatus.decode(payload), throwsFormatException);
      expect(() => DeviceInformation.decode(payload), throwsFormatException);
    }
  });
  test('unsupported versions are explicit, not interpreted as version 1', () {
    for (final version in [0, 2, 255]) {
      expect(
        () => DeviceInformation.decode(
          [...vectors['information']!]..[0] = version,
        ),
        throwsA(isA<UnsupportedProtocol>()),
      );
      expect(
        () => LiveStatus.decode([...vectors['connected']!]..[0] = version),
        throwsA(isA<UnsupportedProtocol>()),
      );
    }
  });
  test('invalid states and stale address combinations are rejected', () {
    for (final payload in [
      [...vectors['connected']!]..[1] = 4,
      [...vectors['connected']!]..[11] = 2,
      [...vectors['disconnected']!]..[2] = 1,
      [...vectors['disconnected']!]..[6] = 204,
      [...vectors['connected']!]..[6] = 128,
      [...vectors['connected']!]..setRange(2, 6, [0, 0, 0, 0]),
    ]) {
      expect(() => LiveStatus.decode(payload), throwsFormatException);
    }
    expect(
      () => DeviceInformation.decode(
        [...vectors['information']!]..setRange(1, 7, List.filled(6, 0)),
      ),
      throwsFormatException,
    );
  });
  test('UUID constants match firmware', () {
    final firmware = File('../../firmware/include/ble_protocol.h')
        .readAsStringSync();
    for (final uuid in [
      cueLinkServiceUuid,
      cueLinkInformationUuid,
      cueLinkStatusUuid,
    ]) {
      expect(firmware, contains('"$uuid"'));
    }
  });
}
