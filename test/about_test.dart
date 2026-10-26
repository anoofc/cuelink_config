import 'package:cuelink_config/about.dart';
import 'package:cuelink_config/ble/controller.dart';
import 'package:cuelink_config/ble/protocol.dart';
import 'package:cuelink_config/config/client.dart';
import 'package:cuelink_config/main.dart';
import 'package:cuelink_config/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';

import 'fake_ble.dart';

class AboutBle extends FakeBle implements ConfigWire {
  int writes = 0, reads = 0;
  @override
  Future<void> writeConfig(String id, List<int> bytes) async {
    writes++;
  }

  @override
  Future<List<int>> readConfig(String id) async {
    reads++;
    return [];
  }

  @override
  Future<List<int>> readInformation(String id) async {
    reads++;
    return testInfo;
  }

  @override
  Future<List<int>> readStatus(String id) async {
    reads++;
    return testStatus;
  }
}

class ProfileLauncher extends UrlLauncherPlatform {
  @override
  LinkDelegate? get linkDelegate => null;
  final calls = <(String, PreferredLaunchMode)>[];
  bool succeeds = true;
  bool throws = false;
  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    calls.add((url, options.mode));
    if (throws) throw Exception('Unavailable');
    return succeeds;
  }
}

void main() {
  late ProfileLauncher launcher;
  setUp(() {
    launcher = ProfileLauncher();
    final previous = UrlLauncherPlatform.instance;
    UrlLauncherPlatform.instance = launcher;
    addTearDown(() => UrlLauncherPlatform.instance = previous);
    PackageInfo.setMockInitialValues(
      appName: 'CueLink Config',
      packageName: 'com.example.cuelinkConfig',
      version: '2.3.4',
      buildNumber: '56',
      buildSignature: '',
    );
  });

  Future<void> cleanup(
    WidgetTester tester,
    CueLinkController controller,
  ) async {
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    await tester.pump();
  }

  Future<CueLinkController> show(
    WidgetTester tester, {
    bool connected = false,
  }) async {
    final controller = CueLinkController(AboutBle());
    if (connected) {
      controller.selected = testDevice;
      controller.session = SessionState.connected;
      controller.information = DeviceInformation.decode(testInfo);
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: cueLinkTheme(),
        home: AboutScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('Home opens About disconnected without BLE traffic', (
    tester,
  ) async {
    final ble = AboutBle();
    final controller = CueLinkController(ble);
    await tester.pumpWidget(CueLinkApp(controller: controller));
    await tester.tap(find.byTooltip('About'));
    await tester.pumpAndSettle();
    expect(find.text('About'), findsOneWidget);
    expect(find.text('2.3.4 (build 56)'), findsOneWidget);
    expect(find.text('Connected device'), findsNothing);
    expect(ble.writes, 0);
    expect(ble.reads, 0);
    expect(ble.scans, 0);
    expect(ble.connects, 0);
    expect(launcher.calls, isEmpty);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Connect your controller'), findsOneWidget);
    await cleanup(tester, controller);
  });

  testWidgets(
    'connected metadata uses cached state and hides after disconnect',
    (tester) async {
      final controller = await show(tester, connected: true);
      expect(find.text('Connected device'), findsOneWidget);
      expect(find.text('CueLink-4455\nFirmware 0.4.0'), findsOneWidget);
      await controller.disconnect();
      await tester.pumpAndSettle();
      expect(find.text('Connected device'), findsNothing);
      expect(find.text('2.3.4 (build 56)'), findsOneWidget);
      expect((controller.configWire as AboutBle).reads, 0);
      await cleanup(tester, controller);
    },
  );

  testWidgets('Home also opens About connected without configuration reads', (
    tester,
  ) async {
    final ble = AboutBle();
    final controller = CueLinkController(ble)
      ..selected = testDevice
      ..session = SessionState.connected
      ..information = DeviceInformation.decode(testInfo)
      ..status = LiveStatus.decode(testStatus)
      ..receivedAt = DateTime.now();
    await tester.pumpWidget(CueLinkApp(controller: controller));
    await tester.tap(find.byTooltip('About'));
    await tester.pumpAndSettle();
    expect(find.text('CueLink-4455\nFirmware 0.4.0'), findsOneWidget);
    expect(ble.reads, 0);
    expect(ble.writes, 0);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Disconnect'), findsOneWidget);
    await cleanup(tester, controller);
  });

  testWidgets('support and developer links launch only on tap, externally', (
    tester,
  ) async {
    final controller = await show(tester);
    for (final label in ['Message on LinkedIn', 'LinkedIn', 'GitHub']) {
      await tester.ensureVisible(find.text(label));
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }
    expect(launcher.calls, [
      (
        'https://www.linkedin.com/in/anoofc/',
        PreferredLaunchMode.externalApplication,
      ),
      (
        'https://www.linkedin.com/in/anoofc/',
        PreferredLaunchMode.externalApplication,
      ),
      ('https://github.com/anoofc', PreferredLaunchMode.externalApplication),
    ]);
    await cleanup(tester, controller);
  });

  for (final throws in [false, true]) {
    testWidgets('profile launch failure is readable (throws=$throws)', (
      tester,
    ) async {
      launcher.succeeds = false;
      launcher.throws = throws;
      final controller = await show(tester);
      await tester.ensureVisible(find.text('Message on LinkedIn'));
      await tester.tap(find.text('Message on LinkedIn'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'Could not open https://www.linkedin.com/in/anoofc/',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await cleanup(tester, controller);
    });
  }

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets(
      'About scrolls at 320px and 200% text on $platform with licenses',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 568));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final controller = CueLinkController(FakeBle());
        await tester.pumpWidget(
          MaterialApp(
            theme: cueLinkTheme().copyWith(platform: platform),
            home: AboutScreen(controller: controller),
          ),
        );
        await tester.pumpAndSettle();
        final scroll = tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position;
        for (
          double offset = 0;
          offset < scroll.maxScrollExtent;
          offset += 180
        ) {
          scroll.jumpTo(offset);
          await tester.pump();
          expect(tester.takeException(), isNull);
        }
        scroll.jumpTo(scroll.maxScrollExtent);
        await tester.pump();
        expect(
          find.textContaining('For use with CueLink hardware.'),
          findsOneWidget,
        );
        await tester.ensureVisible(find.text('Third-party Licenses'));
        await tester.runAsync(() async {
          await tester.tap(find.text('Third-party Licenses'));
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 250));
        });
        await tester.pumpAndSettle();
        expect(find.byType(LicensePage), findsOneWidget);
        expect(find.text('SwiftProtobuf (iOS BLE dependency)'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.text('About'), findsOneWidget);
        await cleanup(tester, controller);
      },
    );
  }
}
