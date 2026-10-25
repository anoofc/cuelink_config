# Configuration navigation

The connected home header retains the approved compact CueLink mark with a 12-pixel gap and the title **CueLink Config**. Its configuration entry is now **Configuration**.

Opening that entry creates one configuration route/client bound to the selected device ID. On the route's first frame, it automatically loads authoritative settings. Request initiation is outside `build`, and both navigation and load/retry have synchronous guards against repeated taps. The initial view shows Loading settings and a progress indicator; it never presents editable default values. All four loaded buttons and the existing Routing/Network actions populate from the returned configuration. Refresh remains available after a successful load.

A failed load shows a concise error and Retry, with optional error details and physical-authorization instructions when relevant. A changed/disconnected device invalidates the load through the existing client and hides this route's configuration/actions. Retry cannot send the old client's request to another device.

There is no automatic refresh on widget rebuild, live-status update, or return from an editor. Existing Save/Discard semantics remain: unsaved Back navigation prompts for confirmation; Keep editing retains the local draft, and explicit discard is still respected. Successful subpage saves update the existing client/cache and are reflected by the parent without another load.

Changed files:

- `lib/main.dart`: connected title, Configuration entry, and one-route navigation guard.
- `lib/config/screens.dart`: initial automatic load, loading/error/retry UI, and device-bound settings display.
- `test/config_navigation_test.dart`: end-to-end widget coverage for automatic load, rapid taps/rebuilds/retry, all settings actions, button/routing saves, unsaved-change retention, no reload on subpage returns, and device changes during loading.
- `test/ui_review_test.dart`: controlled authorization fixture and connected-home/entry render captures at normal/narrow sizes and increased text scaling.
- `docs/configuration_navigation.md`: this record.

Verification completed: Flutter analysis reported no issues, all 62 Flutter tests passed, and the signed iOS release build passed. Connected-home/configuration renders were checked at 390px and 320px, including 200% text scaling. Software-rendered screenshots are under ignored `build/ui_review/`. Physical-device BLE/navigation checks remain separate; this task does not change the transport, firmware, trigger execution, or native branding resources.
