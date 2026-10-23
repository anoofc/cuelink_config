import 'dart:typed_data';

const cueLinkServiceUuid = 'c0e10001-7a6b-4c8d-9e10-5b2f034a0001';
const cueLinkInformationUuid = 'c0e10002-7a6b-4c8d-9e10-5b2f034a0001';
const cueLinkStatusUuid = 'c0e10003-7a6b-4c8d-9e10-5b2f034a0001';

class UnsupportedProtocol implements Exception {
  const UnsupportedProtocol(this.version);
  final int version;
  @override
  String toString() =>
      'Unsupported CueLink protocol $version. Update the app or controller.';
}

ByteData _payload(List<int> bytes) {
  if (bytes.isEmpty) throw const FormatException('Empty CueLink payload.');
  if (bytes.any((byte) => byte < 0 || byte > 255)) {
    throw const FormatException('Invalid byte value.');
  }
  if (bytes[0] != 1) throw UnsupportedProtocol(bytes[0]);
  if (bytes.length != 12) {
    throw const FormatException('Expected a 12-byte CueLink payload.');
  }
  return ByteData.sublistView(Uint8List.fromList(bytes));
}

class DeviceInformation {
  const DeviceInformation(this.identifier, this.firmware, this.capabilities);
  final String identifier;
  final String firmware;
  final int capabilities;

  factory DeviceInformation.decode(List<int> bytes) {
    final data = _payload(bytes);
    final identity = bytes.sublist(1, 7);
    if (identity.every((b) => b == 0) || identity.every((b) => b == 255)) {
      throw const FormatException('Invalid controller identity.');
    }
    return DeviceInformation(
      identity
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join()
          .toUpperCase(),
      '${bytes[7]}.${bytes[8]}.${bytes[9]}',
      data.getUint16(10, Endian.little),
    );
  }
}

enum WifiState {
  notConfigured('Not configured'),
  connecting('Connecting'),
  connected('Connected'),
  reconnecting('Reconnecting');

  const WifiState(this.label);
  final String label;
}

class LiveStatus {
  const LiveStatus(
    this.wifi,
    this.ipv4,
    this.rssi,
    this.uptimeSeconds,
    this.diagnostics,
  );
  final WifiState wifi;
  final String? ipv4;
  final int? rssi;
  final int uptimeSeconds;
  final bool diagnostics;

  factory LiveStatus.decode(List<int> bytes) {
    final data = _payload(bytes);
    if (bytes[1] >= WifiState.values.length || bytes[11] > 1) {
      throw const FormatException('Invalid Wi-Fi state or controller mode.');
    }
    final wifi = WifiState.values[bytes[1]];
    final ip = bytes.sublist(2, 6);
    final unavailable = bytes[6] == 0x80;
    if (wifi != WifiState.connected &&
        (ip.any((b) => b != 0) || !unavailable)) {
      throw const FormatException(
        'Disconnected controller exposed stale addressing.',
      );
    }
    if (wifi == WifiState.connected &&
        (ip.every((b) => b == 0) || unavailable)) {
      throw const FormatException(
        'Connected controller has no address or signal.',
      );
    }
    return LiveStatus(
      wifi,
      wifi == WifiState.connected ? ip.join('.') : null,
      unavailable ? null : data.getInt8(6),
      data.getUint32(7, Endian.little),
      bytes[11] == 1,
    );
  }
}
