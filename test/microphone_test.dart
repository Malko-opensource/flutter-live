import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_live/src/controller.dart';
import 'package:flutter_live/src/models.dart';

import 'controller_test.dart' show FakeLive;
import 'fake_desktop.dart';

class ObservedLive extends FakeLive {
  int sent = 0;
  @override
  void sendAudio(Uint8List bytes) {
    sent++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'local test uses selected input without API and stops capture',
    () async {
      final desktop = FakeDesktop(), live = ObservedLive();
      final c = InterpreterController(desktop: desktop, live: live);
      await c.refreshInputDevices();
      expect(c.inputDevices.map((d) => d.uid), ['test-bt', 'test-usb']);
      await c.testMicrophone('test-bt');
      expect(desktop.selectedUID, 'test-bt');
      expect(desktop.capturing, isTrue);
      final bytes = Uint8List(640);
      final samples = ByteData.sublistView(bytes);
      for (var i = 0; i < 640; i += 2) {
        samples.setInt16(i, 6500, Endian.little);
      }
      desktop.input.add(bytes);
      await Future<void>.delayed(Duration.zero);
      expect(c.inputDbfs, closeTo(-14.05, .03));
      expect(live.starts, 0);
      expect(live.sent, 0);
      await c.stopMicrophoneTest();
      expect(c.testingMicrophone, isFalse);
      expect(desktop.capturing, isFalse);
      expect(c.inputLevel, 0);
      c.dispose();
    },
  );

  test(
    'closing during test startup cancels pending microphone request',
    () async {
      final desktop = FakeDesktop();
      final c = InterpreterController(desktop: desktop, live: ObservedLive());
      final start = c.testMicrophone('test-usb');
      await c.stopMicrophoneTest();
      await start;
      expect(desktop.capturing, isFalse);
      c.dispose();
    },
  );

  test(
    'translation captures chosen device; test cannot replace active session',
    () async {
      final desktop = FakeDesktop(), live = ObservedLive();
      final c = InterpreterController(desktop: desktop, live: live)
        ..apiKey = 'test-key'
        ..inputDeviceUID = 'test-usb';
      await c.start();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(desktop.selectedUID, 'test-usb');
      expect(c.phase, SessionPhase.listening);
      await c.testMicrophone('test-bt');
      expect(desktop.selectedUID, 'test-usb');
      expect(c.testingMicrophone, isFalse);
      await c.stop();
      c.dispose();
    },
  );
}
