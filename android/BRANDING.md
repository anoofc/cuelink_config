# Staged CueLink Android icons

This checkout has no Android runner, Gradle project, or application manifest. Per the requested scope, only the approved icon resources are staged here; Android application support was not generated.

`app/src/main/res/` contains the supplied files unchanged:

- Legacy `mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png`.
- `drawable/ic_launcher_background.xml`, `ic_launcher_foreground.xml`, and `ic_launcher_monochrome.xml`.
- Adaptive icon definitions for API 26+ and API 33+.

When an Android runner is added, merge these resources without changing their 108dp viewport or 48dp foreground geometry. Use compile SDK 33 or later for the monochrome definition. The application manifest must reference `android:icon="@mipmap/ic_launcher"`; if `android:roundIcon` is declared, point it to the same resource. There is no current manifest or compile SDK to verify.

There is no launcher-icon generator configuration. Treat these approved resources as authoritative; a future generator must not overwrite them with Flutter defaults. Flutter-generated local properties/plugin registration files are ignored and do not constitute an Android runner.
