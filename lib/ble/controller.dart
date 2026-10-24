import 'dart:async';

import 'package:flutter/foundation.dart';

import 'protocol.dart';
import '../config/client.dart';
import 'transport.dart';

enum SessionState { disconnected, connecting, connected }

class CueLinkController extends ChangeNotifier {
  CueLinkController(this._transport) {
    _radioSubscription = _transport.radio.listen(
      _radioChanged,
      onError: (Object error) {
        _radioChanged(RadioState.unavailable);
        message =
            'Bluetooth is unavailable. Retry after checking iPhone Settings.';
        _emit();
      },
    );
    _freshnessTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (status != null) _emit();
    });
  }
  final BleTransport _transport;
  ConfigWire? get configWire =>
      _transport is ConfigWire ? _transport as ConfigWire : null;
  RadioState radio = RadioState.unknown;
  SessionState session = SessionState.disconnected;
  bool scanning = false;
  String? message;
  final Map<String, DiscoveredController> _devices = {};
  List<DiscoveredController> get devices => List.unmodifiable(_devices.values);
  DiscoveredController? selected;
  DeviceInformation? information;
  LiveStatus? status;
  DateTime? receivedAt;
  bool get fresh =>
      session == SessionState.connected &&
      receivedAt != null &&
      DateTime.now().difference(receivedAt!) < const Duration(seconds: 5);
  bool get busy => _starting || session == SessionState.connecting;
  StreamSubscription<RadioState>? _radioSubscription;
  StreamSubscription<DiscoveredController>? _scanSubscription;
  StreamSubscription<LinkEvent>? _connectionSubscription;
  StreamSubscription<List<int>>? _notificationSubscription;
  Timer? _scanTimer, _connectionTimer, _freshnessTimer;
  int _epoch = 0, _scanEpoch = 0;
  bool _disposed = false;
  bool _starting = false;
  Future<void> _cleanup = Future<void>.value();
  int _intent = 0;

  String get radioMessage => switch (radio) {
    RadioState.ready => 'Bluetooth ready',
    RadioState.poweredOff => 'Bluetooth is off. Enable it in iPhone Settings.',
    RadioState.unauthorized => 'Bluetooth permission denied. Allow CueLink Config in Settings > Privacy & Security > Bluetooth.',
    RadioState.unsupported => 'Bluetooth LE is not supported on this device.',
    RadioState.unknown => 'Checking Bluetooth. Try Scan again shortly.',
    RadioState.unavailable =>
      'Bluetooth is unavailable. Check iPhone Settings and retry.',
  };

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void _radioChanged(RadioState value) {
    radio = value;
    if (value != RadioState.ready) {
      unawaited(stopScan());
      if (session != SessionState.disconnected || _starting) {
        unawaited(disconnect(reason: radioMessage));
      }
    }
    _emit();
  }

  Future<void> scan() async {
    if (_disposed || busy || session == SessionState.connected) return;
    final intent = ++_intent;
    await _stopScan();
    if (_disposed || intent != _intent) return;
    if (radio != RadioState.ready) {
      message = radioMessage;
      _emit();
      return;
    }
    final epoch = ++_scanEpoch;
    _devices.clear();
    message = null;
    scanning = true;
    _emit();
    _scanTimer = Timer(const Duration(seconds: 10), () {
      unawaited(stopScan());
      message = _devices.isEmpty
          ? 'Scan timed out. Enable App connection on your controller, then retry.'
          : 'Scan finished. Choose a controller to connect.';
      _emit();
    });
    _scanSubscription = _transport.scan().listen(
      (device) {
        if (_disposed || epoch != _scanEpoch) return;
        _devices[device.id] = DiscoveredController(
          id: device.id,
          name: device.name.isNotEmpty
              ? device.name
              : (_devices[device.id]?.name ?? 'CueLink controller'),
          scanRssi: device.scanRssi,
        );
        _emit();
      },
      onError: (Object error) {
        if (_disposed || epoch != _scanEpoch) return;
        unawaited(stopScan());
        message = 'Scan failed. Check Bluetooth permission and retry. ($error)';
        _emit();
      },
      onDone: () {
        if (epoch == _scanEpoch) unawaited(stopScan());
      },
    );
  }

  Future<void> stopScan() {
    ++_intent;
    return _stopScan();
  }

  Future<void> _stopScan() async {
    ++_scanEpoch;
    _scanTimer?.cancel();
    _scanTimer = null;
    final subscription = _scanSubscription;
    _scanSubscription = null;
    scanning = false;
    _emit();
    await _cancel(subscription);
  }

  Future<void> connect(DiscoveredController device) async {
    if (_disposed || busy) return;
    _starting = true;
    final intent = ++_intent;
    try {
      await _stopScan();
      await _endSession();
      if (_disposed || intent != _intent) return;
      selected = device;
      information = null;
      status = null;
      receivedAt = null;
      if (radio != RadioState.ready) {
        message = radioMessage;
        _emit();
        return;
      }
      message = null;
      session = SessionState.connecting;
      final epoch = ++_epoch;
      var loading = false;
      _connectionTimer = Timer(const Duration(seconds: 12), () {
        if (epoch == _epoch) {
          unawaited(
            disconnect(
              reason:
                  'Connection timed out. Enable discovery and tap Reconnect.',
            ),
          );
        }
      });
      _emit();
      _connectionSubscription = _transport
          .connect(device.id)
          .listen(
            (event) {
              if (_disposed || epoch != _epoch) return;
              if (event == LinkEvent.connected && !loading) {
                loading = true;
                unawaited(_load(device.id, epoch));
              } else if (event == LinkEvent.disconnected) {
                unawaited(
                  disconnect(
                    reason: 'Controller disconnected. Enable discovery and reconnect manually.',
                  ),
                );
              }
            },
            onError: (Object error) {
              if (epoch == _epoch) {
                unawaited(
                  disconnect(
                    reason:
                        'Connection failed. Retry with discovery enabled. ($error)',
                  ),
                );
              }
            },
            onDone: () {
              if (epoch == _epoch) {
                unawaited(
                  disconnect(
                    reason: 'Controller connection ended. Reconnect manually.',
                  ),
                );
              }
            },
          );
    } catch (error) {
      if (!_disposed && intent == _intent) {
        await disconnect(
          reason: 'Connection failed. Check Bluetooth and retry. ($error)',
        );
      }
    } finally {
      _starting = false;
      _emit();
    }
  }

  Future<void> _load(String id, int epoch) async {
    try {
      final infoBytes = await _transport
          .readInformation(id)
          .timeout(const Duration(seconds: 5));
      if (_disposed || epoch != _epoch) return;
      final info = DeviceInformation.decode(infoBytes);
      final statusBytes = await _transport
          .readStatus(id)
          .timeout(const Duration(seconds: 5));
      if (_disposed || epoch != _epoch) return;
      final initial = LiveStatus.decode(statusBytes);
      information = info;
      status = initial;
      receivedAt = DateTime.now();
      _notificationSubscription = _transport
          .statusNotifications(id)
          .listen(
            (bytes) {
              if (_disposed || epoch != _epoch) return;
              try {
                status = LiveStatus.decode(bytes);
                receivedAt = DateTime.now();
                _emit();
              } catch (error) {
                unawaited(disconnect(reason: _protocolError(error)));
              }
            },
            onError: (Object error) {
              if (epoch == _epoch) {
                unawaited(
                  disconnect(
                    reason:
                        'Status subscription failed. Reconnect manually. ($error)',
                  ),
                );
              }
            },
            onDone: () {
              if (epoch == _epoch) {
                unawaited(
                  disconnect(reason: 'Live status ended. Reconnect manually.'),
                );
              }
            },
          );
      session = SessionState.connected;
      _connectionTimer?.cancel();
      _emit();
    } catch (error) {
      if (!_disposed && epoch == _epoch) {
        await disconnect(reason: _protocolError(error));
      }
    }
  }

  String _protocolError(Object error) => switch (error) {
    UnsupportedProtocol() => error.toString(),
    FormatException() =>
      'Malformed CueLink data. Disconnecting; check firmware compatibility.',
    TimeoutException() =>
      'Controller read timed out. Enable discovery and reconnect.',
    _ => 'Could not read controller information. Reconnect and retry. ($error)',
  };

  Future<void> disconnect({String? reason}) {
    ++_intent;
    return _endSession(reason: reason);
  }

  Future<void> _endSession({String? reason}) {
    ++_epoch;
    _connectionTimer?.cancel();
    _connectionTimer = null;
    final notifications = _notificationSubscription;
    final connection = _connectionSubscription;
    _notificationSubscription = null;
    _connectionSubscription = null;
    session = SessionState.disconnected;
    message = reason;
    _emit();
    // A fresh connection must await any previous native disconnect, even if
    // the UI already shows Disconnected. This prevents overlapping sessions.
    _cleanup = _cleanup.then((_) async {
      await _cancel(notifications);
      await _cancel(connection);
    });
    return _cleanup;
  }

  Future<void> _cancel(StreamSubscription<dynamic>? subscription) async {
    try {
      await subscription?.cancel();
    } catch (error) {
      debugPrint('BLE subscription cleanup failed: $error');
    }
  }

  Future<void> showDiscovery() async {
    await disconnect();
    selected = null;
    information = null;
    status = null;
    receivedAt = null;
    _emit();
  }

  Future<void> suspend() async {
    await stopScan();
    await disconnect(
      reason: selected == null
          ? null
          : 'App paused. Data is stale. Tap Reconnect when you return.',
    );
  }

  @override
  void dispose() {
    _disposed = true;
    ++_epoch;
    ++_scanEpoch;
    ++_intent;
    _scanTimer?.cancel();
    _connectionTimer?.cancel();
    _freshnessTimer?.cancel();
    unawaited(_shutdown());
    super.dispose();
  }

  Future<void> _shutdown() async {
    await _cleanup;
    await _cancel(_scanSubscription);
    await _cancel(_notificationSubscription);
    await _cancel(_connectionSubscription);
    await _cancel(_radioSubscription);
    try {
      await _transport.dispose();
    } catch (error) {
      debugPrint('BLE transport cleanup failed: $error');
    }
  }
}
