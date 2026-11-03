import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_live/src/controller.dart';
import 'package:flutter_live/src/live/gemini_live_client.dart';
import 'package:flutter_live/src/models.dart';

import 'fake_desktop.dart';

class FakeLive extends GeminiLiveClient {
  final updates = StreamController<LiveEvent>.broadcast();
  int starts = 0;
  @override
  Stream<LiveEvent> get events => updates.stream;
  @override
  Future<void> start(SessionConfig config) async {
    starts++;
    updates.add(const LiveEvent(LiveEventKind.ready));
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {
    await updates.close();
    await super.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('megaphone uses dBFS attack, hysteresis, release and configurable threshold', () async {
    final desktop = FakeDesktop(), live = FakeLive();
    final c = InterpreterController(desktop: desktop, live: live)
      ..apiKey = 'fake-key';
    Future<void> feed(int amplitude, int chunks) async {
      final bytes = Uint8List(640);
      final samples = ByteData.sublistView(bytes);
      for (var i = 0; i < bytes.length; i += 2) {
        samples.setInt16(i, amplitude, Endian.little);
      }
      for (var i = 0; i < chunks; i++) {
        desktop.input.add(bytes);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }

    await c.start();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await feed(6500, 1);
    expect(c.inputDbfs, closeTo(-14.05, .03));
    expect(c.mascotClip, 'listen'); // Ignore a single loud click.
    await feed(0, 1);
    await feed(6500, 4);
    expect(c.mascotClip, 'sing'); // 80 ms is not sustained loudness.
    await feed(6500, 1);
    expect(c.mascotClip, 'megaphone');
    await feed(3277, 25); // -20 dBFS is below entry but above -24 release.
    expect(c.mascotClip, 'megaphone');
    await feed(1000, 26); // Ordinary speech continues below the release band.
    expect(c.mascotClip, 'sing');
    c.setMegaphoneThreshold(-30);
    await feed(1600, 5); // Roughly -26 dBFS now exceeds the user threshold.
    expect(c.mascotClip, 'megaphone');
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(c.mascotClip, 'listen'); // Release even when packets stop arriving.
    await feed(6500, 5);
    expect(c.mascotClip, 'megaphone');
    await c.pause();
    expect(c.mascotClip, 'idle');
    expect(c.inputDbfs, -96);
    await c.start();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(c.mascotClip, 'listen');
    c.setMegaphoneThreshold(double.nan);
    expect(c.megaphoneThresholdDbfs, -30);
    c.setMegaphoneThreshold(1);
    expect(c.megaphoneThresholdDbfs, -6);
    await c.stop();
    c.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
  test(
    'input activity sings, holds short pauses, and resets on stop',
    () async {
      final desktop = FakeDesktop(), live = FakeLive();
      final c = InterpreterController(desktop: desktop, live: live)
        ..apiKey = 'fake-key';
      await c.start();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(c.mascotClip, 'listen');
      final loud = Uint8List(640); // 20 ms, 16 kHz mono PCM16.
      final samples = ByteData.sublistView(loud);
      for (var i = 0; i < loud.length; i += 2) {
        samples.setInt16(i, 1800, Endian.little);
      }
      desktop.input.add(loud);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.mascotClip, 'listen'); // A brief click must not trigger it.
      desktop.input.add(Uint8List(640));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      for (var i = 0; i < 3; i++) {
        desktop.input.add(loud);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(c.mascotClip, 'sing');
      live.updates.add(const LiveEvent(LiveEventKind.output, text: 'Hello'));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(c.mascotClip, 'sing'); // Input activity wins during duplex output.
      desktop.input.add(Uint8List(640));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(c.mascotClip, 'sing');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(
        c.mascotClip,
        'speak',
      ); // No further packets also releases the pose.
      for (var i = 0; i < 3; i++) {
        desktop.input.add(loud);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(c.mascotClip, 'sing');
      await c.pause();
      expect(c.mascotClip, 'idle');
      await c.start();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(c.mascotClip, 'listen');
      await c.stop();
      c.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 400));
    },
  );
  test(
    'interrupt clears both playback queues and pause stops capture',
    () async {
      final desktop = FakeDesktop(), live = FakeLive();
      final c = InterpreterController(desktop: desktop, live: live)
        ..apiKey = 'fake-key';
      await c.start();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(desktop.capturing, true);
      live.updates.add(
        LiveEvent(LiveEventKind.audio, bytes: Uint8List(1920 * 5)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(desktop.played, isNotEmpty);
      live.updates.add(const LiveEvent(LiveEventKind.interrupted));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final played = desktop.played.length;
      expect(desktop.cleared, isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(desktop.played.length, played);
      await c.pause();
      expect(desktop.capturing, false);
      expect(c.phase, SessionPhase.paused);
      await c.start();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(live.starts, 2);
      expect(desktop.capturing, true);
      await c.stop();
      expect(desktop.capturing, false);
      c.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    },
  );
  test(
    'preview uses no microphone or live session and stop clears text',
    () async {
      final desktop = FakeDesktop(), live = FakeLive();
      final c = InterpreterController(desktop: desktop, live: live);
      await c.preview();
      expect(live.starts, 0);
      expect(desktop.capturing, false);
      expect(c.caption.translation, isNotEmpty);
      await c.stop();
      expect(c.caption.translation, isEmpty);
      c.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    },
  );
}
