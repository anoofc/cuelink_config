import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import 'protocol.dart';
import '../config/client.dart';

enum RadioState {
  unknown,
  ready,
  poweredOff,
  unauthorized,
  unsupported,
  unavailable,
}

enum LinkEvent { connecting, connected, disconnected }

class DiscoveredController {
  const DiscoveredController({
    required this.id,
    required this.name,
    required this.scanRssi,
  });
  final String id;
  final String name;
  final int scanRssi;
}

abstract class BleTransport {
  Stream<RadioState> get radio;
  Stream<DiscoveredController> scan();
  Stream<LinkEvent> connect(String id);
  Future<List<int>> readInformation(String id);
  Future<List<int>> readStatus(String id);
  Stream<List<int>> statusNotifications(String id);
  Future<void> dispose();
}

class ReactiveBleTransport implements BleTransport, ConfigWire {
  final FlutterReactiveBle _ble = FlutterReactiveBle();
  final Uuid _service = Uuid.parse(cueLinkServiceUuid);

  @override
  Stream<RadioState> get radio => _ble.statusStream.map(
    (status) => switch (status) {
      BleStatus.ready => RadioState.ready,
      BleStatus.poweredOff => RadioState.poweredOff,
      BleStatus.unauthorized => RadioState.unauthorized,
      BleStatus.unsupported => RadioState.unsupported,
      BleStatus.unknown => RadioState.unknown,
      _ => RadioState.unavailable,
    },
  );

  @override
  Stream<DiscoveredController> scan() => _ble
      .scanForDevices(withServices: [_service], scanMode: ScanMode.lowLatency)
      .map(
        (device) => DiscoveredController(
          id: device.id,
          name: device.name,
          scanRssi: device.rssi,
        ),
      );

  @override
  Stream<LinkEvent> connect(String id) => _ble
      .connectToDevice(
        id: id,
        servicesWithCharacteristicsToDiscover: {
          _service: [
            Uuid.parse(cueLinkInformationUuid),
            Uuid.parse(cueLinkStatusUuid),
            Uuid.parse('c0e10004-7a6b-4c8d-9e10-5b2f034a0001'),
            Uuid.parse('c0e10005-7a6b-4c8d-9e10-5b2f034a0001'),
          ],
        },
        connectionTimeout: const Duration(seconds: 8),
      )
      .map(
        (update) => switch (update.connectionState) {
          DeviceConnectionState.connected => LinkEvent.connected,
          DeviceConnectionState.disconnected => LinkEvent.disconnected,
          _ => LinkEvent.connecting,
        },
      );

  QualifiedCharacteristic _characteristic(String id, String uuid) =>
      QualifiedCharacteristic(
        deviceId: id,
        serviceId: _service,
        characteristicId: Uuid.parse(uuid),
      );
  @override
  Future<List<int>> readInformation(String id) =>
      _ble.readCharacteristic(_characteristic(id, cueLinkInformationUuid));
  @override
  Future<List<int>> readStatus(String id) =>
      _ble.readCharacteristic(_characteristic(id, cueLinkStatusUuid));
  @override
  Stream<List<int>> statusNotifications(String id) =>
      _ble.subscribeToCharacteristic(_characteristic(id, cueLinkStatusUuid));
  @override
  Future<void> writeConfig(String id, List<int> bytes) =>
      _ble.writeCharacteristicWithResponse(
        _characteristic(id, 'c0e10004-7a6b-4c8d-9e10-5b2f034a0001'),
        value: bytes,
      );
  @override
  Future<List<int>> readConfig(String id) => _ble.readCharacteristic(
    _characteristic(id, 'c0e10005-7a6b-4c8d-9e10-5b2f034a0001'),
  );
  @override
  Future<void> dispose() => _ble.deinitialize();
}
