# About page

Home's information icon opens About whether disconnected or connected. The page
uses the existing logo, theme, spacing, SafeArea, and a scroll view constrained to
600 logical pixels. Text wraps at larger accessibility sizes.

`lib/about.dart` contains the page and the shared developer profile URLs. Installed
app metadata comes from `package_info_plus`, requested once per page instance.
Connected device information is rendered from `CueLinkController`'s existing
name and firmware values, only while connected. About never queries BLE settings.
External links use `url_launcher` with `LaunchMode.externalApplication`; a false
result or exception produces a readable SnackBar. They never send messages.

The copyright and proprietary application statements describe CueLink Config.
Flutter's Third-party Licenses page lists dependency notices separately. Flutter
generates Dart/plugin notices; `lib/third_party_licenses.dart` additionally
registers the unmodified SwiftProtobuf native iOS BLE runtime license stored in
`assets/licenses/swift_protobuf_LICENSE.txt` (from the resolved Swift package).

## Verification

- `flutter pub get` and `flutter analyze` pass.
- Existing tests and About tests pass. About coverage includes navigation from
  disconnected and connected Home, cached metadata, disconnect updates, installed
  version formatting, no BLE reads/writes, exact external link destinations and
  launch mode, readable failure messages, scrolling and licenses navigation.
- Widget layouts pass at 320 logical pixels and 200% text under iOS and Android
  themes. The existing visual review captures About at 390px/100%, 320px/160%,
  and 320px/200%. PNG assets are decoded before capture.
- Signed iOS release build succeeds. Its Info.plist has version 0.1.0/build 1.
  The packaged asset bundle contains the new plugin notices and native license.
- This checkout has no Android Gradle runner (only staged icon resources), so an
  Android native build/device check is unavailable.

Physical-device checks remain: installed version display through the native
plugin; browser/LinkedIn handoff and return on iOS and Android; VoiceOver/TalkBack;
live controller metadata. Existing app lifecycle handling still applies when an
external application is opened. No app installation or data removal was performed.

## Commands

Run in `flutter/cuelink_config`, using the project's Flutter SDK:

```sh
flutter pub get
flutter analyze
flutter test
FLUTTER_ROOT=/Users/anoofc/Documents/PROJECTS_X/Flutter/flutter flutter test test/ui_review_test.dart --dart-define=CUE_UI_REVIEW=true
flutter build ios --release
```

Build artifact: `build/ios/iphoneos/Runner.app`.
