# CueLink Config

The Flutter Bluetooth companion for CueLink Controller: discovery, live identity/
Wi-Fi status, and physically authorized configuration of buttons, routing and
network settings. Four buttons support up to four OSC, UDP or USB MIDI triggers
per button. Credentials remain protected and are not logged or cached on disk.

Configuration transfer uses capability-gated MTU-aware frames, protected response
notifications and scoped save verification on updated firmware. Older firmware
uses the legacy default-MTU/read-based path. See [performance measurements,
protocol details, rebuild/install commands and physical acceptance steps](../../firmware/docs/configuration_performance.md).
The ≤5-second target has passed latency simulation for normal negotiated MTUs;
physical iPhone/controller acceptance is still pending. MTU-23 near-limit transfers
are safe but slower, and Wi-Fi credential testing may take up to 30 seconds.

## Run and test

The installed SDK is at `/Users/anoofc/Documents/PROJECTS_X/Flutter/flutter/bin`.
Use `flutter` from that directory if it is not on PATH:

```sh
flutter pub get
flutter analyze
flutter test
flutter build ios --no-codesign
```

The project remains iOS-only, with its original bundle ID, signing team, and iOS
15 target. Open `ios/Runner.xcworkspace` in Xcode and build/run on your physical
iPhone using the existing signing setup. The unsigned build cannot be installed
as-is. Nothing is uploaded or installed automatically.

On the controller, hold B4 five seconds to enter diagnostics. Navigate with B1/B2
to **App connection**, then press B3 for a 120-second discovery window. In the
app, allow Bluetooth, tap **Scan controllers**, and choose **Connect**. Scans stop
after ten seconds. Connected sessions may continue after controller discovery
expires, but reconnect requires discovery to still be active or a new B3 press.

The UI uses graphite, cyan, white text, safe areas, scrolling, large touch targets,
and system text scaling. It shows no status until actual reads arrive. BLE scan
RSSI and live Wi-Fi RSSI are separate. Last-known values are clearly marked stale
after disconnect, or after five seconds without status. Backgrounding cancels
scans and disconnects; returning requires a manual **Reconnect**.

## Structure

- `lib/ble/protocol.dart`: fixed UUIDs and strict, versioned payload decoding.
- `lib/ble/transport.dart`: small BLE interface and flutter_reactive_ble adapter.
- `lib/ble/controller.dart`: scan/session state, deadlines, subscription ownership,
  cancellation, stale data, and manual reconnect.
- `lib/main.dart`: dark discovery/overview UI and app lifecycle policy.
- `lib/config/client.dart`: CRC-framed transfers, serialized writes, notifications/recovery, revision and authoritative readback verification, and timing diagnostics.
- `lib/config/screens.dart`: existing button/trigger/routing/network editors and explicit draft handling.
- `test/`: shared firmware golden-vector decoding, malformed/unsupported data,
  fake-transport lifecycle tests, and accessible UI checks. Fakes are test-only.

Pinned dependency: **flutter_reactive_ble 5.6.0**, BSD-3-Clause (Signify).
[Package API and iOS permission requirements](https://pub.dev/packages/flutter_reactive_ble/versions/5.6.0).
Only `NSBluetoothAlwaysUsageDescription` is added; no location, local-network, or
background Bluetooth permissions are requested.

Full UUIDs, byte-level field definitions, dependency licenses, firmware lifecycle,
and physical test checklist are in [the BLE protocol document](../../firmware/docs/ble_protocol.md).
The public information/status characteristics remain 12 bytes. Protected configuration
uses the separately versioned transport, with 20–244-byte frames depending on capability and negotiated capacity.
Protocol fixtures are shared from `../../firmware/docs/ble_protocol_vectors.json`,
so run tests with the firmware/app directories in their existing repository layout.

No real-device BLE testing has been performed by the coding agent.
