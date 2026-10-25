import 'dart:async';

import 'package:cuelink_config/ble/controller.dart';
import 'package:cuelink_config/ble/protocol.dart';
import 'package:cuelink_config/ble/transport.dart';
import 'package:cuelink_config/config/client.dart';
import 'package:cuelink_config/config/screens.dart';
import 'package:cuelink_config/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'config_test.dart' show Wire;
import 'fake_ble.dart';

class NavigationWire extends Wire {
  int starts = 0;
  bool failReads = false;
  Completer<void>? gate;
  final ids = <String>[];
  @override
  Future<List<int>> readConfig(String id) async {
    await gate?.future;
    if (failReads) throw StateError('Bluetooth read failed');
    return super.readConfig(id);
  }

  @override
  Future<void> writeConfig(String id, List<int> bytes) async {
    ids.add(id);
    if (bytes[1] == 1) starts++;
    await super.writeConfig(id, bytes);
  }
}

class ConfigBle extends FakeBle implements ConfigWire {
  ConfigBle(this.wire);
  final NavigationWire wire;
  @override
  Future<List<int>> readConfig(String id) => wire.readConfig(id);
  @override
  Future<void> writeConfig(String id, List<int> bytes) =>
      wire.writeConfig(id, bytes);
}

CueLinkController connected(NavigationWire wire) {
  final c = CueLinkController(ConfigBle(wire));
  c.selected = testDevice;
  c.information = DeviceInformation.decode([...testInfo]..[10] = 0x7f);
  c.status = LiveStatus.decode(testStatus);
  c.receivedAt = DateTime.now();
  c.session = SessionState.connected;
  return c;
}

Future<void> reveal(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      200,
      scrollable: find.byType(Scrollable).last,
    );
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

Future<void> cleanup(WidgetTester tester, CueLinkController c) async {
  await tester.pumpWidget(const SizedBox.shrink());
  c.dispose();
  await tester.pump();
}

void main() {
  testWidgets(
    'one tap opens Configuration and auto-loads once despite repeated taps/rebuilds',
    (tester) async {
      final wire = NavigationWire()..gate = Completer<void>();
      final c = connected(wire);
      await tester.binding.setSurfaceSize(const Size(320, 700));
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      await tester.pumpWidget(CueLinkApp(controller: c));
      expect(find.text('CueLink Config'), findsOneWidget);
      final entry = find.widgetWithText(FilledButton, 'Configuration');
      await reveal(tester, entry);
      final press = tester.widget<FilledButton>(entry).onPressed!;
      press();
      press(); // Same frame: guard must work before the disabled repaint.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.byType(ConfigurationScreen, skipOffstage: false),
        findsOneWidget,
      );
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Load settings'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('B1 ·'), findsNothing);
      for (var i = 0; i < 5; i++) {
        c.notifyListeners();
        await tester.pump();
      }
      expect(wire.starts, 1);
      wire.gate!.complete();
      await tester.pumpAndSettle();
      expect(wire.operations.map((o) => o['op']), ['read']);
      for (var b = 1; b <= 4; b++) {
        await reveal(tester, find.textContaining('B$b ·'));
        expect(find.textContaining('B$b ·'), findsOneWidget);
      }
      await reveal(tester, find.text('Routing'));
      expect(find.text('Routing'), findsOneWidget);
      await reveal(tester, find.text('Network'));
      expect(find.text('Network'), findsOneWidget);
      expect(wire.ids.toSet(), {testDevice.id});
      expect(tester.takeException(), isNull);
      await cleanup(tester, c);
    },
  );
  testWidgets(
    'initial failure shows Retry without editable defaults, then loads successfully',
    (tester) async {
      final wire = NavigationWire()..failReads = true;
      final c = connected(wire);
      await tester.pumpWidget(CueLinkApp(controller: c));
      final entry = find.widgetWithText(FilledButton, 'Configuration');
      await reveal(tester, entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.text('Couldn’t load settings. Try again.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.textContaining('B1 ·'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(wire.starts, 1);
      wire.failReads = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(wire.starts, 2);
      expect(find.textContaining('B1 ·'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      await cleanup(tester, c);
    },
  );
  testWidgets(
    'save and subpage returns retain verified state and do not auto-refresh drafts',
    (tester) async {
      final wire = NavigationWire();
      final c = connected(wire);
      await tester.pumpWidget(CueLinkApp(controller: c));
      final entry = find.widgetWithText(FilledButton, 'Configuration');
      await reveal(tester, entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('B1 ·'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Draft button');
      await tester.pump();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Discard unsaved changes?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('Draft button'), findsOneWidget);
      expect(wire.operations.map((o) => o['op']), ['read']);
      await reveal(tester, find.text('Save button'));
      await tester.tap(find.text('Save button'));
      await tester.pumpAndSettle();
      expect(wire.writes, 1);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(wire.operations.map((o) => o['op']), ['read', 'button', 'read']);
      await reveal(tester, find.text('B1 · Draft button'));
      await reveal(tester, find.text('Routing'));
      await tester.tap(find.text('Routing'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use master destinations'));
      await tester.pump();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('Unsaved changes'), findsOneWidget);
      await reveal(tester, find.text('Save routing'));
      await tester.tap(find.text('Save routing'));
      await tester.pumpAndSettle();
      expect(wire.writes, 2);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(wire.operations.map((o) => o['op']), [
        'read',
        'button',
        'read',
        'routing',
        'read',
      ]);
      await reveal(tester, find.text('Network'));
      await tester.tap(find.text('Network'));
      await tester.pumpAndSettle();
      await reveal(tester, find.byType(TextField).first);
      await tester.enterText(find.byType(TextField).first, 'Unsaved Wi-Fi');
      await tester.pump();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('Unsaved Wi-Fi'), findsOneWidget);
      expect(wire.operations.length, 5);
      expect(tester.takeException(), isNull);
      await cleanup(tester, c);
    },
  );
  testWidgets(
    'device changes during loading cannot expose or edit another device’s data',
    (tester) async {
      final wire = NavigationWire()..gate = Completer<void>();
      final c = connected(wire);
      await tester.pumpWidget(CueLinkApp(controller: c));
      final entry = find.widgetWithText(FilledButton, 'Configuration');
      await reveal(tester, entry);
      await tester.tap(entry);
      await tester.pump();
      c.selected = const DiscoveredController(
        id: 'other-device',
        name: 'Other CueLink',
        scanRssi: -50,
      );
      c.notifyListeners();
      wire.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('Connection changed.'), findsOneWidget);
      expect(find.textContaining('B1 ·'), findsNothing);
      expect(find.text('Routing'), findsNothing);
      expect(find.text('Network'), findsNothing);
      expect(wire.ids.toSet(), {testDevice.id});
      await cleanup(tester, c);
    },
  );
}
