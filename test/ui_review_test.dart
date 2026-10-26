import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:cuelink_config/about.dart';
import 'package:cuelink_config/brand.dart';
import 'package:cuelink_config/ble/controller.dart';
import 'package:cuelink_config/ble/protocol.dart';
import 'package:cuelink_config/config/client.dart';
import 'package:cuelink_config/config/models.dart';
import 'package:cuelink_config/config/screens.dart';
import 'package:cuelink_config/main.dart';
import 'package:cuelink_config/ui.dart';

import 'fake_ble.dart';
import 'config_widget_test.dart' show NoWrites;

const capture = bool.fromEnvironment('CUE_UI_REVIEW');
const boundaryKey = ValueKey('review-capture');

Future<void> reveal(WidgetTester tester, Finder finder) =>
    Scrollable.ensureVisible(tester.element(finder), alignment: 0.15);

Future<void> snapshot(WidgetTester tester, String name) async {
  await tester.pump();
  expect(tester.takeException(), isNull, reason: name);
  if (!capture) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(boundaryKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/ui_review/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

class ReviewBle extends FakeBle implements ConfigWire {
  @override
  Future<void> writeConfig(String id, List<int> bytes) async {}
  @override
  Future<List<int>> readConfig(String id) async => [];
}

// Controlled screen-review fixture: initial opening now loads automatically.
class ReviewClient extends ConfigClient {
  ReviewClient(super.wire, super.id);
  @override
  Future<void> load() async {
    uncertain = true;
    state = 'Failed: Physical authorization required';
    emit();
  }
}

void main() {
  setUpAll(() async {
    final sdk = Platform.environment['FLUTTER_ROOT'];
    if (capture && sdk != null) {
      final loader = FontLoader('Roboto')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              File('$sdk/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf')
                  .readAsBytesSync(),
            ),
          ),
        );
      await loader.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              File(
                '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
              ).readAsBytesSync(),
            ),
          ),
        );
      await icons.load();
    }
  });
  for (final profile in [
    (390.0, 844.0, 1.0),
    (320.0, 700.0, 1.6),
    (320.0, 700.0, 2.0),
  ]) {
    testWidgets('all editors fit ${profile.$1}px at ${profile.$3} text scale', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(profile.$1, profile.$2));
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(top: 44, bottom: 34);
      tester.platformDispatcher.textScaleFactorTestValue = profile.$3;
      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
        tester.view.resetDevicePixelRatio();
        tester.view.resetPadding();
        tester.view.resetViewPadding();
        tester.view.resetViewInsets();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      final wire = NoWrites();
      final client = ReviewClient(wire, 'ios-test-id');
      final fixture = jsonDecode(
        File('../../firmware/docs/configuration_vector.json')
            .readAsStringSync(),
      ) as Json;
      client.configuration = Configuration.parse(fixture);
      final first = client.configuration!.buttons[0];
      first.slots.add(first.slots.first);
      final controller = CueLinkController(ReviewBle());
      controller.selected = testDevice;
      controller.information = DeviceInformation.decode(testInfo);
      controller.session = SessionState.connected;
      controller.status = LiveStatus.decode(testStatus);
      controller.receivedAt = DateTime.now();
      final prefix = '${profile.$1.toInt()}-${profile.$3}';
      Future<void> show(String name, Widget page) async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundaryKey,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: cueLinkTheme(),
              home: page,
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 350));
        if (page is AboutScreen) {
          // Decode the PNG outside the widget test's fake clock before capture.
          await tester.runAsync(
            () => precacheImage(
              const AssetImage(CueLinkBrand.logoOnDark),
              tester.element(find.byType(AboutScreen)),
            ),
          );
          await tester.pump();
        }
        await snapshot(tester, '$prefix-$name-top');
        if (name == 'transfer') {
          expect(find.text('Cancel transfer'), findsOneWidget);
        }
        final scroll = find.byType(Scrollable);
        if (scroll.evaluate().isNotEmpty) {
          tester
              .state<ScrollableState>(scroll.first)
              .position
              .jumpTo(
                tester
                    .state<ScrollableState>(scroll.first)
                    .position
                    .maxScrollExtent,
              );
          await tester.pump(const Duration(milliseconds: 350));
          await snapshot(tester, '$prefix-$name-bottom');
        }
      }

      Future<void> keyboard(String name, Finder target) async {
        await reveal(tester, target);
        await tester.tap(target);
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pumpAndSettle();
        await reveal(tester, target);
        await snapshot(tester, '$prefix-$name-keyboard');
        tester.view.resetViewInsets();
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
      }

      final loaded = client.configuration;
      PackageInfo.setMockInitialValues(
        appName: 'CueLink Config',
        packageName: 'com.example.cuelinkConfig',
        version: '0.1.0',
        buildNumber: '1',
        buildSignature: '',
      );
      await show('about', AboutScreen(controller: controller));
      client.configuration = null;
      await show(
        'authorization',
        ConfigurationScreen(controller: controller, client: client),
      );
      client.configuration = loaded;
      client.uncertain = false;
      client.state = 'Connected · Settings loaded';
      await show(
        'settings',
        ConfigurationScreen(controller: controller, client: client),
      );
      client.busy = true;
      client.state = 'Loading settings…';
      await show(
        'transfer',
        ConfigurationScreen(controller: controller, client: client),
      );
      client.busy = false;
      client.state = 'Connected · Settings loaded';
      await show('four-triggers', ButtonEditor(client: client, index: 0));
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Add trigger'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(
              find
                  .byWidgetPredicate(
                    (w) => w is IconButton && w.tooltip == 'Move trigger up',
                  )
                  .first,
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(
              find
                  .byWidgetPredicate(
                    (w) => w is IconButton && w.tooltip == 'Move trigger down',
                  )
                  .last,
            )
            .onPressed,
        isNull,
      );
      await reveal(tester, find.byType(TextField).first);
      await tester.enterText(find.byType(TextField).first, 'Long name 12');
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      await reveal(tester, find.byType(TextField).first);
      await snapshot(tester, '$prefix-button-keyboard');
      tester.view.resetViewInsets();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      client.configuration = Configuration.parse({
        ...client.configuration!.toJson(),
        'revision': 1,
      });
      client.emit();
      await tester.pump();
      expect(find.text('Long name 12'), findsOneWidget);
      await reveal(tester, find.text('Discard changes'));
      await snapshot(tester, '$prefix-conflict');
      await tester.tap(find.text('Discard changes'));
      await tester.pumpAndSettle();
      expect(find.text('Discard unsaved changes?'), findsOneWidget);
      await snapshot(tester, '$prefix-unsaved-confirmation');
      await show(
        'osc',
        TriggerEditor(
          initial: first.slots.first,
          routing: client.configuration!.routing,
        ),
      );
      await keyboard('osc', find.byType(TextField).first);
      await show(
        'udp',
        TriggerEditor(
          initial: first.slots[1],
          routing: client.configuration!.routing,
        ),
      );
      await keyboard('udp', find.byType(TextField).first);
      await show(
        'midi',
        TriggerEditor(
          initial: first.slots[2],
          routing: client.configuration!.routing,
        ),
      );
      await keyboard('midi', find.byType(TextField).first);
      await show('routing', RoutingEditor(client: client));
      await reveal(tester, find.text('Add destination'));
      await tester.tap(find.text('Add destination'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('IP address'));
      await snapshot(tester, '$prefix-destination');
      await keyboard('routing', find.byType(TextField).first);
      await show(
        'network',
        NetworkEditor(client: client, controller: controller),
      );
      final mode = find.byType(DropdownButtonFormField<String>);
      await reveal(tester, mode);
      await tester.tap(mode);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Replace password').last);
      await tester.pumpAndSettle();
      final password = find.byType(TextField).at(1);
      await reveal(tester, password);
      await tester.enterText(password, 'password123');
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      await reveal(tester, password);
      await snapshot(tester, '$prefix-network-keyboard');
      tester.view.resetViewInsets();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await reveal(tester, find.text('DHCP'));
      await tester.tap(find.text('DHCP'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Static IPv4'));
      await snapshot(tester, '$prefix-static-ip');
      expect(wire.writes, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      client.dispose();
      controller.dispose();
    });
    testWidgets('discovery fits ${profile.$1}px at ${profile.$3} text scale', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(profile.$1, profile.$2));
      tester.platformDispatcher.textScaleFactorTestValue = profile.$3;
      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      final model = CueLinkController(ReviewBle());
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: CueLinkApp(controller: model),
        ),
      );
      await tester.pumpAndSettle();
      await snapshot(tester, '${profile.$1.toInt()}-${profile.$3}-discovery');
      expect(find.text('Stop'), findsNothing);
      await reveal(tester, find.text('How to connect'));
      await tester.tap(find.text('How to connect'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Hold B4 for 5 seconds'), findsOneWidget);
      expect(tester.takeException(), isNull);
      model.selected = testDevice;
      model.session = SessionState.connected;
      model.information = DeviceInformation.decode([...testInfo]..[10] = 0x7f);
      model.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('CueLink Config'), findsOneWidget);
      final image = tester.widget<Image>(find.byType(Image).first);
      await tester.runAsync(
        () => precacheImage(
          image.image,
          tester.element(find.byType(Image).first),
        ),
      );
      await tester.pump();
      await snapshot(
        tester,
        '${profile.$1.toInt()}-${profile.$3}-connected-home',
      );
      await reveal(tester, find.text('Configuration'));
      await snapshot(
        tester,
        '${profile.$1.toInt()}-${profile.$3}-configuration-entry',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      model.dispose();
    });
  }
}
