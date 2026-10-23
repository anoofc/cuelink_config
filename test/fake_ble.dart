import 'dart:async';

import 'package:cuelink_config/ble/transport.dart';

const testDevice = DiscoveredController(
  id: 'ios-test-id',
  name: 'CueLink-4455',
  scanRssi: -63,
);
const testInfo = [1, 2, 17, 34, 51, 68, 85, 0, 4, 0, 15, 0];
const testStatus = [1, 2, 192, 0, 2, 1, 204, 4, 3, 2, 1, 0];

class FakeBle extends BleTransport {
  final radioEvents = StreamController<RadioState>.broadcast(sync: true);
  final discoveries = StreamController<DiscoveredController>.broadcast(
    sync: true,
  );
  final links = <StreamController<LinkEvent>>[];
  final notifications = <StreamController<List<int>>>[];
  int scans = 0, connects = 0, activeNotifications = 0;
  List<int> info = testInfo;
  Completer<List<int>>? pendingInformation;
  Completer<void>? pendingDisconnect;
  @override
  Stream<RadioState> get radio => radioEvents.stream;
  @override
  Stream<DiscoveredController> scan() {
    scans++;
    return discoveries.stream;
  }

  @override
  Stream<LinkEvent> connect(String id) {
    connects++;
    final stream = StreamController<LinkEvent>(
      sync: true,
      onCancel: () async {
        await pendingDisconnect?.future;
      },
    );
    links.add(stream);
    return stream.stream;
  }

  @override
  Future<List<int>> readInformation(String id) async =>
      pendingInformation == null ? info : await pendingInformation!.future;
  @override
  Future<List<int>> readStatus(String id) async => testStatus;
  @override
  Stream<List<int>> statusNotifications(String id) {
    final stream = StreamController<List<int>>(
      sync: true,
      onListen: () => activeNotifications++,
      onCancel: () async {
        activeNotifications--;
        await Future<void>.value();
      },
    );
    notifications.add(stream);
    return stream.stream;
  }

  // No native resources. Subscription cancellation is asserted by the tests.
  @override
  Future<void> dispose() async {}
}
