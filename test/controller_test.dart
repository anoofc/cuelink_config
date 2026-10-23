import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cuelink_config/ble/controller.dart';
import 'package:cuelink_config/ble/transport.dart';

import 'fake_ble.dart';

void main() {
  test('scan is user initiated, deduplicated, bounded, and retryable', () {
    fakeAsync((clock) {
      final ble = FakeBle();
      final model = CueLinkController(ble);
      ble.radioEvents.add(RadioState.ready);
      expect(ble.scans, 0);
      unawaited(model.scan());
      clock.flushMicrotasks();
      ble.discoveries.add(testDevice);
      ble.discoveries.add(
        const DiscoveredController(
          id: 'ios-test-id',
          name: 'CueLink-4455',
          scanRssi: -58,
        ),
      );
      expect(model.devices.length, 1);
      expect(model.devices.single.scanRssi, -58);
      ble.discoveries.add(
        const DiscoveredController(id: 'ios-test-id', name: '', scanRssi: -57),
      );
      expect(model.devices.single.name, 'CueLink-4455');
      expect(model.devices.single.scanRssi, -57);
      clock.elapse(const Duration(seconds: 10));
      expect(model.scanning, false);
      expect(ble.discoveries.hasListener, false);
      unawaited(model.scan());
      clock.flushMicrotasks();
      expect(ble.scans, 2);
      unawaited(model.stopScan());
      clock.flushMicrotasks();
      model.dispose();
      clock.flushMicrotasks();
    });
  });
  test(
    'off, denied, unsupported, empty timeout, and scan failure are explicit',
    () {
      fakeAsync((clock) {
        final ble = FakeBle();
        final model = CueLinkController(ble);
        for (final state in [
          RadioState.poweredOff,
          RadioState.unauthorized,
          RadioState.unsupported,
        ]) {
          ble.radioEvents.add(state);
          unawaited(model.scan());
          clock.flushMicrotasks();
          expect(model.message, model.radioMessage);
          expect(ble.scans, 0);
        }
        ble.radioEvents.add(RadioState.ready);
        unawaited(model.scan());
        clock.flushMicrotasks();
        clock.elapse(const Duration(seconds: 10));
        expect(model.message, contains('timed out'));
        unawaited(model.scan());
        clock.flushMicrotasks();
        ble.discoveries.addError(StateError('scan error'));
        clock.flushMicrotasks();
        expect(model.message, contains('Scan failed'));
        expect(model.scanning, false);
        model.dispose();
        clock.flushMicrotasks();
      });
    },
  );
  test('read then subscribe once, stale disconnect, manual retry and background cleanup', () {
    fakeAsync((clock) {
      final ble = FakeBle();
      final model = CueLinkController(ble);
      ble.radioEvents.add(RadioState.ready);
      unawaited(model.connect(testDevice));
      clock.flushMicrotasks();
      ble.links.last.add(LinkEvent.connected);
      ble.links.last.add(LinkEvent.connected);
      clock.flushMicrotasks();
      expect(model.session, SessionState.connected);
      expect(model.information!.identifier, '021122334455');
      expect(ble.activeNotifications, 1);
      ble.notifications.last.add([...testStatus]..[6] = 200);
      expect(model.status!.rssi, -56);
      expect(model.fresh, true);
      model.receivedAt = DateTime.now().subtract(const Duration(seconds: 6));
      expect(model.fresh, false);
      unawaited(model.disconnect());
      clock.flushMicrotasks();
      expect(model.status, isNotNull);
      expect(model.fresh, false);
      expect(ble.activeNotifications, 0);
      clock.elapse(const Duration(seconds: 20));
      expect(ble.connects, 1);
      unawaited(model.connect(testDevice));
      clock.flushMicrotasks();
      ble.links.last.add(LinkEvent.connected);
      clock.flushMicrotasks();
      expect(ble.activeNotifications, 1);
      unawaited(model.suspend());
      clock.flushMicrotasks();
      expect(model.session, SessionState.disconnected);
      expect(ble.activeNotifications, 0);
      clock.elapse(const Duration(seconds: 10));
      expect(ble.connects, 2);
      model.dispose();
      clock.flushMicrotasks();
    });
  });
  test(
    'connection timeout, failure and unsupported protocol terminate attempts',
    () {
      fakeAsync((clock) {
        final ble = FakeBle();
        final model = CueLinkController(ble);
        ble.radioEvents.add(RadioState.ready);
        unawaited(model.connect(testDevice));
        clock.flushMicrotasks();
        clock.elapse(const Duration(seconds: 12));
        expect(model.message, contains('timed out'));
        expect(model.session, SessionState.disconnected);
        unawaited(model.connect(testDevice));
        clock.flushMicrotasks();
        ble.links.last.addError(StateError('cannot connect'));
        clock.flushMicrotasks();
        expect(model.message, contains('Connection failed'));
        ble.info = [...testInfo]..[0] = 2;
        unawaited(model.connect(testDevice));
        clock.flushMicrotasks();
        ble.links.last.add(LinkEvent.connected);
        clock.flushMicrotasks();
        expect(model.message, contains('Unsupported CueLink protocol 2'));
        expect(model.session, SessionState.disconnected);
        expect(ble.activeNotifications, 0);
        model.dispose();
        clock.flushMicrotasks();
      });
    },
  );
  test(
    'late read after background cannot subscribe, and double connect is gated',
    () {
      fakeAsync((clock) {
        final ble = FakeBle()..pendingInformation = Completer<List<int>>();
        final model = CueLinkController(ble);
        ble.radioEvents.add(RadioState.ready);
        unawaited(model.connect(testDevice));
        unawaited(model.connect(testDevice));
        clock.flushMicrotasks();
        expect(ble.connects, 1);
        ble.links.last.add(LinkEvent.connected);
        clock.flushMicrotasks();
        unawaited(model.suspend());
        clock.flushMicrotasks();
        ble.pendingInformation!.complete(testInfo);
        clock.flushMicrotasks();
        expect(model.session, SessionState.disconnected);
        expect(ble.notifications, isEmpty);
        model.dispose();
        clock.flushMicrotasks();
      });
    },
  );
  test(
    'malformed notifications disconnect without continuing a stale stream',
    () {
      fakeAsync((clock) {
        final ble = FakeBle();
        final model = CueLinkController(ble);
        ble.radioEvents.add(RadioState.ready);
        unawaited(model.connect(testDevice));
        clock.flushMicrotasks();
        ble.links.last.add(LinkEvent.connected);
        clock.flushMicrotasks();
        ble.notifications.last.add([1, 2]);
        clock.flushMicrotasks();
        expect(model.message, contains('Malformed'));
        expect(model.session, SessionState.disconnected);
        expect(model.fresh, false);
        expect(ble.activeNotifications, 0);
        model.dispose();
        clock.flushMicrotasks();
      });
    },
  );

  test('manual reconnect waits for the previous native disconnect', () {
    fakeAsync((clock) {
      final ble = FakeBle();
      final model = CueLinkController(ble);
      ble.radioEvents.add(RadioState.ready);
      unawaited(model.connect(testDevice));
      clock.flushMicrotasks();
      ble.links.last.add(LinkEvent.connected);
      clock.flushMicrotasks();
      ble.pendingDisconnect = Completer<void>();
      unawaited(model.disconnect());
      clock.flushMicrotasks();
      unawaited(model.connect(testDevice));
      clock.flushMicrotasks();
      expect(ble.connects, 1);
      ble.pendingDisconnect!.complete();
      clock.flushMicrotasks();
      expect(ble.connects, 2);
      model.dispose();
      clock.flushMicrotasks();
    });
  });
}
