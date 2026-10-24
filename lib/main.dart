import 'dart:async';

import 'package:flutter/material.dart';

import 'ble/controller.dart';
import 'ble/transport.dart';
import 'config/screens.dart';

void main() => runApp(const CueLinkApp());

class CueLinkApp extends StatefulWidget {
  const CueLinkApp({super.key, this.controller});
  final CueLinkController? controller;
  @override
  State<CueLinkApp> createState() => _CueLinkAppState();
}

class _CueLinkAppState extends State<CueLinkApp> with WidgetsBindingObserver {
  late final CueLinkController controller;
  @override
  void initState() {
    super.initState();
    controller = widget.controller ?? CueLinkController(ReactiveBleTransport());
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(controller.suspend());
    }
    // Resume deliberately leaves the session disconnected for manual reconnect.
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.controller == null) controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ColorScheme.fromSeed(
      seedColor: const Color(0xff53e0ec),
      brightness: Brightness.dark,
      primary: const Color(0xff53e0ec),
      surface: const Color(0xff1a2128),
    );
    return MaterialApp(
      title: 'CueLink Config',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colors,
        scaffoldBackgroundColor: const Color(0xff101418),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xff101418),
          centerTitle: false,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(48, 52),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(48, 52),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
        ),
      ),
      home: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => Scaffold(
          appBar: AppBar(title: const Text('CueLink Config')),
          body: SafeArea(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: SingleChildScrollView(
                key: ValueKey(
                  controller.selected == null ? 'discovery' : 'overview',
                ),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: controller.selected == null
                        ? _Discovery(controller: controller)
                        : _Overview(controller: controller),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Discovery extends StatelessWidget {
  const _Discovery({required this.controller});
  final CueLinkController controller;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Eyebrow('CONTROLLER DISCOVERY'),
        const SizedBox(height: 12),
        Text(
          'Your controller.\nWithin reach.',
          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Connect over Bluetooth to view live status and configure your CueLink.',
          style: TextStyle(fontSize: 16, height: 1.5, color: Color(0xffb6c2cd)),
        ),
        const SizedBox(height: 24),
        _Badge(
          label: c.radio == RadioState.ready
              ? 'Bluetooth ready'
              : 'Bluetooth needs attention',
          active: c.radio == RadioState.ready,
        ),
        if (c.radio != RadioState.ready) ...[
          const SizedBox(height: 12),
          _Notice(c.radioMessage),
        ],
        if (c.message != null) ...[
          const SizedBox(height: 12),
          _Notice(c.message!),
        ],
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: c.scanning ? null : () => unawaited(c.scan()),
              icon: const Icon(Icons.bluetooth_searching),
              label: Text(c.scanning ? 'Scanning…' : 'Scan controllers'),
            ),
            OutlinedButton(
              onPressed: c.scanning ? () => unawaited(c.stopScan()) : null,
              child: const Text('Stop'),
            ),
            if (c.message != null)
              TextButton(
                onPressed: c.scanning ? null : () => unawaited(c.scan()),
                child: const Text('Retry'),
              ),
          ],
        ),
        if (c.scanning) ...[
          const SizedBox(height: 20),
          const LinearProgressIndicator(minHeight: 2),
          const SizedBox(height: 10),
          const Text('Looking for CueLink controllers • up to 10 seconds'),
        ],
        const SizedBox(height: 24),
        if (c.devices.isEmpty)
          const _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.touch_app_outlined,
                  color: Color(0xff53e0ec),
                  size: 30,
                ),
                SizedBox(height: 14),
                Text(
                  'Enable App connection',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 10),
                Text(
                  'Hold B4 for 5 seconds to open diagnostics. Use B1/B2 to find App connection, then press B3. Your controller is discoverable for 120 seconds.',
                  style: TextStyle(height: 1.6, color: Color(0xffb6c2cd)),
                ),
                SizedBox(height: 12),
                Text(
                  'No controllers found yet.',
                  style: TextStyle(color: Color(0xffb6c2cd)),
                ),
              ],
            ),
          )
        else
          ...c.devices.map(
            (device) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      device.name,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'BLE scan RSSI: ${device.scanRssi} dBm',
                      style: const TextStyle(color: Color(0xffb6c2cd)),
                    ),
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: () => unawaited(c.connect(device)),
                      child: const Text('Connect'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 24),
        const Text(
          'Live status · authenticated configuration',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xff8f9ba7)),
        ),
      ],
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.controller});
  final CueLinkController controller;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    final live = c.status;
    final stale = live != null && !c.fresh;
    final connected = c.session == SessionState.connected;
    final label = c.busy
        ? 'Connecting…'
        : connected
        ? (stale ? 'Connected • status stale' : 'Connected')
        : 'Disconnected';
    String statusLabel(String label) => stale ? 'Last $label' : label;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Eyebrow('CONTROLLER OVERVIEW'),
        const SizedBox(height: 12),
        Text(
          c.selected!.name,
          style: Theme.of(context).textTheme.headlineLarge
              ?.copyWith(fontWeight: FontWeight.w700, color: Colors.white),
        ),
        const SizedBox(height: 16),
        _Badge(label: label, active: connected && !stale),
        if (c.busy) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(minHeight: 2),
        ],
        if (c.message != null) ...[
          const SizedBox(height: 16),
          _Notice(c.message!),
        ],
        if (stale) ...[
          const SizedBox(height: 16),
          const _Notice(
            'Last received values are shown below. Live status is unavailable or stale.',
          ),
        ],
        const SizedBox(height: 24),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Eyebrow('DEVICE'),
              _Datum(
                'Device identifier',
                c.information?.identifier ??
                    (c.busy ? 'Reading…' : 'Unavailable'),
              ),
              _Datum(
                'Firmware version',
                c.information?.firmware ?? 'Unavailable',
              ),
              _Datum('BLE RSSI at discovery', '${c.selected!.scanRssi} dBm'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Eyebrow('LIVE STATUS'),
              _Datum(
                statusLabel('Wi-Fi state'),
                live?.wifi.label ?? 'Unavailable',
              ),
              _Datum(statusLabel('IPv4 address'), live?.ipv4 ?? 'Unavailable'),
              _Datum(
                statusLabel('Wi-Fi RSSI'),
                live?.rssi == null ? 'Unavailable' : '${live!.rssi} dBm',
              ),
              _Datum(
                statusLabel('uptime'),
                live == null ? 'Unavailable' : _uptime(live.uptimeSeconds),
              ),
              _Datum(
                statusLabel('controller mode'),
                live == null
                    ? 'Unavailable'
                    : live.diagnostics
                    ? 'Diagnostics'
                    : 'Run',
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        if (connected &&
            c.configWire != null &&
            ((c.information?.capabilities ?? 0) & 32) != 0)
          FilledButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => ConfigurationScreen(controller: c),
              ),
            ),
            icon: const Icon(Icons.tune),
            label: const Text('Buttons, routing & network'),
          ),
        const SizedBox(height: 12),
        if (c.busy || c.session != SessionState.disconnected)
          OutlinedButton.icon(
            onPressed: () => unawaited(
              c.disconnect(
                reason: 'Disconnected by you. Tap Reconnect to start a new session.',
              ),
            ),
            icon: const Icon(Icons.link_off),
            label: Text(c.busy ? 'Cancel connection' : 'Disconnect'),
          )
        else
          FilledButton.icon(
            onPressed: () => unawaited(c.connect(c.selected!)),
            icon: const Icon(Icons.bluetooth_connected),
            label: const Text('Reconnect'),
          ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () => unawaited(c.showDiscovery()),
          child: const Text('Find another controller'),
        ),
      ],
    );
  }
}

String _uptime(int seconds) =>
    '${seconds ~/ 3600}h ${(seconds ~/ 60 % 60).toString().padLeft(2, '0')}m ${(seconds % 60).toString().padLeft(2, '0')}s';

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: Color(0xff53e0ec),
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.5,
    ),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: const Color(0xff1a2128),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xff2b3742)),
    ),
    child: child,
  );
}

class _Notice extends StatelessWidget {
  const _Notice(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => _Panel(
    child: Text(
      text,
      style: const TextStyle(color: Color(0xffd8e2eb), height: 1.5),
    ),
  );
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.active});
  final String label;
  final bool active;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Icon(
          Icons.circle,
          size: 10,
          color: active ? const Color(0xff53e0ec) : const Color(0xffe5b56f),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
    ],
  );
}

class _Datum extends StatelessWidget {
  const _Datum(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Color(0xff9eacb9), fontSize: 13),
        ),
        const SizedBox(height: 5),
        SelectableText(
          value,
          style: const TextStyle(fontSize: 19, height: 1.3),
        ),
      ],
    ),
  );
}
