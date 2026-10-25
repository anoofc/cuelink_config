import 'dart:io';
import 'dart:ui' as ui;

import 'package:cuelink_config/brand.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final width in [320.0, 80.0]) {
      testWidgets('approved PNGs render on $brightness at ${width}px', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(Size(width, 180));
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(() async {
          await tester.binding.setSurfaceSize(null);
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        });
        const key = ValueKey('branding-preview');
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(brightness: brightness),
              home: Scaffold(
                backgroundColor: brightness == Brightness.dark
                    ? CueLinkBrand.charcoal
                    : CueLinkBrand.white,
                body: const Center(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CueLinkLogo(height: 64),
                        SizedBox(height: 16),
                        CueLinkLogo(compact: true, height: 40),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final context = tester.element(find.byType(CueLinkLogo).first);
        final images = tester.widgetList<Image>(find.byType(Image)).toList();
        for (final image in images) {
          await tester.runAsync(() => precacheImage(image.image, context));
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          tester
              .widgetList<RawImage>(find.byType(RawImage))
              .every((w) => w.image != null),
          isTrue,
        );
        expect(
          (images.first.image as AssetImage).assetName,
          brightness == Brightness.dark
              ? CueLinkBrand.logoOnDark
              : CueLinkBrand.logoOnLight,
        );
        expect(
          (images.last.image as AssetImage).assetName,
          brightness == Brightness.dark
              ? CueLinkBrand.markOnDark
              : CueLinkBrand.markOnLight,
        );
        if (const bool.fromEnvironment('CUE_UI_REVIEW')) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(key),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            final file = File(
              'build/ui_review/brand-${brightness.name}-${width.toInt()}.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(png!.buffer.asUint8List());
            image.dispose();
          });
        }
      });
    }
  }
}
