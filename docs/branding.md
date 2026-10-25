# Approved CueLink branding integration

The supplied `CueLink_App_Assets/README.md` was read before implementation. Its artwork was copied unchanged. No SVG dependency, logo redesign, new app screen, or delayed splash sequence was introduced. Existing communication, settings, firmware, bundle identifiers, signing, deployment targets, and permissions were not changed by this branding work.

## Files changed for branding

- `assets/branding/`: all 16 supplied PNG/SVG assets copied byte-for-byte. UI code uses only the eight transparent PNG variants; SVG alternatives are retained as supplied files.
- `pubspec.yaml`: asset directory merged into its one existing `flutter:` section.
- `lib/brand.dart`: supplied color/asset constants adapted to the project, plus a reusable accessible `CueLinkLogo` widget. It selects the approved white/orange artwork for dark backgrounds and charcoal/orange artwork for light backgrounds, and preserves aspect ratio with `BoxFit.contain`.
- `lib/main.dart`: connection screen app-bar placeholder replaced by the full wordmark. The connected overview uses the compact four-button mark with the operational label “Controller”. No duplicate CueLink text is placed beside the full logo. The dark/cyan interface theme is retained.
- `lib/ui.dart`: existing app-bar helper accepts an optional widget title without changing other page titles or controls.
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/`: replaced with the supplied catalog and 18 opaque PNGs. Runner already references `AppIcon` in all three configurations. Light/tinted alternative masters were not added to the default catalog.
- `ios/Runner/Assets.xcassets/CueLinkLaunch.imageset/`: approved white wordmark for the existing native launch screen. Unrelated catalogs, including LaunchImage, remain present.
- `ios/Runner/Base.lproj/LaunchScreen.storyboard`: centered aspect-fit wordmark, proportional width, and charcoal background. No artificial launch delay.
- `android/app/src/main/res/`: supplied density/adaptive/monochrome icons staged unchanged. The checkout has no Android runner; the user explicitly chose to stage icons only.
- `android/BRANDING.md`, `android/.gitignore`: explain the staged overlay, future manifest/SDK requirements, and ignore Flutter-generated local files.
- `analysis_options.yaml`: Flutter automatically added the staged Android directory to the existing platform exclusions.
- `test/widget_test.dart`: discovery branding expectation uses the logo widget.
- `test/brand_test.dart`: actual PNG decode/render checks for light/dark backgrounds, full/compact marks, 320px/80px widths, and 200% text settings.
- `docs/branding.md`: this integration and verification record.

Original iOS icons and the launch storyboard were backed up under ignored `build/branding-backup/` before replacement.

The existing UI/firmware refinements in this working tree predate this branding integration; they have not been reverted.

## Checks

- `flutter pub get` completed; no dependency was added.
- `flutter analyze` passed with no issues.
- Signed iOS release build passed (21.4 MB), including native icon-catalog and launch-storyboard compilation.
- All 37 Flutter tests passed, including the responsive UI matrix at 390px/320px and up to 200% text size with keyboard/safe-area insets.
- Light/dark logo renders and the updated narrow discovery header were visually inspected. Captures are in ignored `build/ui_review/brand-*.png` and the existing UI review captures.
- All branding assets match the supplied files by SHA-256. All eight PNGs have real alpha ranging from transparent to opaque.
- All 18 iOS icon images match the supplied assets, have RGB/no alpha, match catalog dimensions/scales, and retain square opaque charcoal corners. No additional default/light/tinted registrations were added.
- Every Android overlay file matches the pack byte-for-byte. Adaptive drawable references resolve, including the API 33 monochrome layer. The supplied foreground padding/placement is retained.
- No icon-generation configuration was found, so none needed removal.

Android manifest resolution, compile-SDK compatibility, and an APK build cannot be completed without an Android runner. The staged XML requires compile SDK 33+. No Android runner was generated, as requested. There is no About screen to update.

Physical checks remain for the iOS launcher mask/cache and native launch-screen appearance, and future Android launchers including themed icons. Software rendering does not establish physical-device verification of the newly branded app.

## Exact rebuild/install commands

From `/Users/anoofc/Documents/PROJECTS_X/CueLink/flutter/cuelink_config`:

```sh
/Users/anoofc/Documents/PROJECTS_X/Flutter/flutter/bin/flutter pub get
/Users/anoofc/Documents/PROJECTS_X/Flutter/flutter/bin/flutter analyze
/Users/anoofc/Documents/PROJECTS_X/Flutter/flutter/bin/flutter test
/Users/anoofc/Documents/PROJECTS_X/Flutter/flutter/bin/flutter build ios --release
xcrun devicectl device install app --device 00008150-000A5D8411F8C01C build/ios/iphoneos/Runner.app
xcrun devicectl device process launch --device 00008150-000A5D8411F8C01C --terminate-existing com.example.cuelinkConfig
```

The install command updates the existing app; no uninstall/data deletion is required. If the old icon remains after installing this build, first reopen the app or restart the device to refresh launcher caching. Do not erase app data just to refresh the icon. iOS may also cache native launch-screen snapshots.

There is no runnable Android build/install command for this checkout yet. After separately adding an Android runner and merging this staged overlay with compile SDK 33+, the standard commands will be `flutter build apk --release` and `flutter install -d <android-device-id> --release`. These are future commands, not checks completed here.

To regenerate software review captures:

```sh
FLUTTER_ROOT=/Users/anoofc/Documents/PROJECTS_X/Flutter/flutter /Users/anoofc/Documents/PROJECTS_X/Flutter/flutter/bin/flutter test --dart-define=CUE_UI_REVIEW=true
```
