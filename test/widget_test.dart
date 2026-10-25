import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cuelink_config/main.dart';
import 'package:cuelink_config/brand.dart';
import 'package:cuelink_config/ble/controller.dart';
import 'package:cuelink_config/ble/protocol.dart';
import 'package:cuelink_config/ble/transport.dart';

import 'fake_ble.dart';

void main() {
  testWidgets(
    'discovery empty state and controls support large text on iPhone width',
    (tester) async {
      final ble = FakeBle();
      final model = CueLinkController(ble);
      ble.radioEvents.add(RadioState.ready);
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(CueLinkApp(controller: model));
      expect(find.byType(CueLinkLogo), findsOneWidget);
      expect(find.text('How to connect'), findsOneWidget);
      expect(find.text('Connect'), findsNothing);
      expect(ble.scans, 0);
      await tester.ensureVisible(find.text('Scan controllers'));
      await tester.pump();
      await tester.tap(find.text('Scan controllers'));
      await tester.pump();
      expect(ble.scans, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      model.dispose();
      await tester.pump();
    },
  );
  testWidgets('overview separates BLE and Wi-Fi signal and marks stale values', (
    tester,
  ) async {
    final ble = FakeBle();
    final model = CueLinkController(ble);
    ble.radioEvents.add(RadioState.ready);
    // Controller lifecycle is tested separately; this test exercises rendering
    // using decoded protocol fixtures without opening a native connection.
    model.selected = testDevice;
    model.information = DeviceInformation.decode(testInfo);
    model.status = LiveStatus.decode(testStatus);
    model.session = SessionState.connected;
    model.receivedAt = DateTime.now();
    await tester.pumpWidget(CueLinkApp(controller: model));
    expect(find.text('BLE RSSI at discovery'), findsOneWidget);
    expect(find.text('Wi-Fi RSSI'), findsOneWidget);
    expect(find.text('-63 dBm'), findsOneWidget);
    expect(find.text('-52 dBm'), findsOneWidget);
    await model.disconnect();
    await tester.pump();
    expect(find.text('Disconnected'), findsOneWidget);
    expect(find.text('Last IPv4 address'), findsOneWidget);
    expect(find.text('Reconnect'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    model.dispose();
    await tester.pump();
  });
}
