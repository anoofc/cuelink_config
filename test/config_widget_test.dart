import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cuelink_config/config/client.dart';
import 'package:cuelink_config/config/models.dart';
import 'package:cuelink_config/config/screens.dart';
import 'package:cuelink_config/ble/controller.dart';

import 'fake_ble.dart';

class NoWrites implements ConfigWire {
  int writes = 0;
  @override
  Future<void> writeConfig(String id, List<int> bytes) async {
    ++writes;
  }

  @override
  Future<List<int>> readConfig(String id) async => [];
}

Configuration fixture() => Configuration.parse(
  jsonDecode(
    File('../../firmware/docs/configuration_vector.json').readAsStringSync(),
  ),
);
Widget host(Widget page) =>
    MaterialApp(theme: ThemeData.dark(useMaterial3: true), home: page);
void main() {
  testWidgets(
    'button editor disables fifth slot and does not transmit draft edits',
    (tester) async {
      final wire = NoWrites(), client = ConfigClient(NoWrites(), 'unused');
      client.dispose();
      final c = ConfigClient(wire, 'device');
      c.configuration = fixture();
      final b = c.configuration!.buttons[0];
      b.slots.add(b.slots.first);
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(host(ButtonEditor(client: c, index: 0)));
      final add = find.widgetWithText(OutlinedButton, 'Add trigger');
      expect(tester.widget<OutlinedButton>(add).onPressed, isNull);
      await tester.enterText(find.byType(TextField).first, 'Live label');
      await tester.pump();
      expect(find.text('Unsaved changes'), findsOneWidget);
      expect(wire.writes, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    },
  );
  testWidgets(
    'network password clears on disconnect without any automatic submission',
    (tester) async {
      final wire = NoWrites(), c = ConfigClient(NoWrites(), 'unused');
      c.dispose();
      final client = ConfigClient(wire, 'device');
      client.configuration = fixture();
      final controller = CueLinkController(FakeBle());
      controller.session = SessionState.connected;
      await tester.pumpWidget(
        host(NetworkEditor(client: client, controller: controller)),
      );
      final mode = find.byType(DropdownButtonFormField<String>);
      await tester.ensureVisible(mode);
      await tester.tap(mode);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Replace password').last);
      await tester.pumpAndSettle();
      final pass = find.byType(TextField).at(1);
      await tester.ensureVisible(pass);
      await tester.enterText(pass, '  test value  ');
      expect(tester.widget<TextField>(pass).obscureText, true);
      await controller.disconnect();
      await tester.pump();
      expect(find.text('New password'), findsNothing);
      expect(wire.writes, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      client.dispose();
      controller.dispose();
      await tester.pump();
    },
  );
  testWidgets(
    'UDP editor preserves hex-only payload and reports text conversion error',
    (tester) async {
      final t = UdpTrigger(true, 'hex', '4100ff', 'none', []);
      await tester.pumpWidget(
        host(TriggerEditor(initial: t, routing: Routing(false, []))),
      );
      final dropdown = find.byType(DropdownButtonFormField<String>).at(1);
      await tester.ensureVisible(dropdown);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Text · supported ASCII').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('cannot be represented'), findsOneWidget);
      expect(find.text('4100ff'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
