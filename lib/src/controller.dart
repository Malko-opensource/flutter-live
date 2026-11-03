import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'audio/pcm_ring_buffer.dart';
import 'live/gemini_live_client.dart';
import 'models.dart';
import 'platform/desktop_bridge.dart';

class InterpreterController extends ChangeNotifier {
  InterpreterController({DesktopBridge? desktop, GeminiLiveClient? live})
    : desktop = desktop ?? DesktopBridge(),
      live = live ?? GeminiLiveClient() {
    this.desktop.onAction((action) {
      switch (action) {
        case 'toggle':
          unawaited(active ? pause() : start());
        case 'stop':
          unawaited(stop());
        case 'overlay':
          unawaited(showOverlay());
        case 'overlayClosed':
          overlayVisible = false;
          _changed();
        case 'inputDevicesChanged':
          unawaited(refreshInputDevices());
        case 'captureError':
          unawaited(_fail('오디오 입력이 중단됐어요. 장치와 접근 권한을 확인해 주세요.'));
      }
    });
    _liveSubscription = this.live.events.listen(_onLive);
    _pump = Timer.periodic(
      const Duration(milliseconds: 20),
      (_) => _pumpAudio(),
    );
  }
  final DesktopBridge desktop;
  final GeminiLiveClient live;
  final caption = CurrentCaption();
  final _playback = PcmRingBuffer(24000 * 2 * 2);
  StreamSubscription<LiveEvent>? _liveSubscription;
  StreamSubscription<Uint8List>? _audioSubscription;
  Timer? _pump, _previewTimer, _nativeUpdate, _inputActivityTimer;
  Timer? _loudInputTimer;
  bool _inputActive = false;
  bool _loudInput = false;
  double _inputAttackMs = 0;
  double _loudAttackMs = 0;
  double inputDbfs = -96;
  double _megaphoneThresholdDbfs = -18;
  double get megaphoneThresholdDbfs => _megaphoneThresholdDbfs;

  void setMegaphoneThreshold(double value) {
    if (!value.isFinite) return;
    _megaphoneThresholdDbfs = value.clamp(-36, -6);
    _loudInputTimer?.cancel();
    _loudInput = false;
    _loudAttackMs = 0;
    _changed();
  }

  int _generation = 0, _sessionEpoch = 0, _startRequest = 0;
  int? _captureStartEpoch;
  Future<void>? _halting;
  bool _pumping = false, _capturing = false, _disposed = false;
  SessionPhase phase = SessionPhase.idle;
  DisplayMode mode = DisplayMode.conversation;
  AudioSource source = AudioSource.microphone;
  String inputDeviceUID = '';
  List<InputDevice> inputDevices = [];
  String inputDevicesError = '';
  bool testingMicrophone = false;
  int _microphoneTestRequest = 0;
  int microphoneTestChunks = 0;

  Future<void> refreshInputDevices() async {
    try {
      inputDevices = await desktop.inputDevices();
      inputDevicesError = '';
    } catch (_) {
      inputDevicesError = '마이크 목록을 불러오지 못했어요. 다시 시도해 주세요.';
    }
    _changed();
  }

  Future<void> testMicrophone(String uid) async {
    if (settingsLocked || testingMicrophone || _disposed) return;
    final request = ++_microphoneTestRequest;
    await stop();
    if (_disposed || request != _microphoneTestRequest) return;
    final epoch = _sessionEpoch;
    testingMicrophone = true;
    microphoneTestChunks = 0;
    error = '';
    _changed();
    try {
      _audioSubscription = desktop.audio.listen(
        (data) {
          if (!testingMicrophone || epoch != _sessionEpoch) return;
          microphoneTestChunks++;
          _measureInput(data);
          _changed();
        },
        onError: (Object _) {
          if (epoch == _sessionEpoch) unawaited(_fail('마이크 입력을 읽을 수 없어요.'));
        },
      );
      await desktop.selectInputDevice(uid);
      if (!testingMicrophone || epoch != _sessionEpoch) return;
      await desktop.startCapture('microphone');
    } on PlatformException catch (e) {
      if (epoch == _sessionEpoch) await _fail(e.message ?? '마이크를 시작할 수 없어요.');
    } catch (_) {
      if (epoch == _sessionEpoch) {
        await _fail('마이크를 시작할 수 없어요. 장치 연결을 확인해 주세요.');
      }
    }
  }

  Future<void> stopMicrophoneTest() async {
    ++_microphoneTestRequest;
    if (testingMicrophone) await stop();
  }

  void _measureInput(Uint8List data) {
    final samples = ByteData.sublistView(data);
    var sum = 0.0;
    for (var i = 0; i + 1 < data.length; i += 2) {
      final x = samples.getInt16(i, Endian.little) / 32768;
      sum += x * x;
    }
    final rms = sqrt(sum / max(1, data.length ~/ 2));
    inputDbfs = max(-96, 20 * log(max(rms, 1e-12)) / ln10);
    inputLevel = min(1, rms * 5);
  }

  MascotSkin _mascotSkin = MascotSkin.hanbok;
  MascotSkin get mascotSkin => _mascotSkin;

  void setMascotSkin(MascotSkin value) {
    if (_mascotSkin == value) return;
    _mascotSkin = value;
    _changed();
  }

  Language first = Language.values[0], second = Language.values[1];
  String apiKey = '', model = 'gemini-3.8-live', error = '';
  double volume = .7, inputLevel = 0;
  bool voiceEnabled = true, overlayVisible = false;

  bool get active => [
    SessionPhase.connecting,
    SessionPhase.listening,
    SessionPhase.translating,
    SessionPhase.reconnecting,
  ].contains(phase);
  bool get settingsLocked => active || phase == SessionPhase.paused;
  int _previewPose = 0;
  String get mascotClip => switch (phase) {
    SessionPhase.listening ||
    SessionPhase.translating when _loudInput => 'megaphone',
    SessionPhase.listening ||
    SessionPhase.translating when _inputActive => 'sing',
    SessionPhase.listening => 'listen',
    SessionPhase.translating => 'speak',
    SessionPhase.connecting ||
    SessionPhase.reconnecting ||
    SessionPhase.failed => 'reconnect',
    SessionPhase.preview => [
      'wave',
      'celebrate',
      'sing',
      'megaphone',
      'listen',
      'speak',
      'idle',
      'reconnect',
    ][_previewPose % 8],
    _ => 'idle',
  };
  String get pairLabel => '${first.label} ↔ ${second.label}';
  String get status => switch (phase) {
    SessionPhase.idle => '통역할 준비가 됐어요',
    SessionPhase.connecting => 'Gemini에 연결 중…',
    SessionPhase.listening => '듣고 있어요',
    SessionPhase.translating => '통역하고 있어요',
    SessionPhase.reconnecting => '연결 재시도 중… 일부 음성이 누락될 수 있어요',
    SessionPhase.paused => '일시 정지됨',
    SessionPhase.failed => error,
    SessionPhase.preview => '디자인 미리보기 · 실제 통역이 아닙니다',
  };

  void setLanguages(Language a, Language b) {
    if (settingsLocked || a.code == b.code) return;
    first = a;
    second = b;
    caption.clear();
    _changed();
  }

  Future<void> setMode(DisplayMode value) async {
    mode = value;
    _changed();
    await setVoice(value == DisplayMode.conversation);
    if (value == DisplayMode.conversation && overlayVisible) {
      overlayVisible = false;
      await _platform(() => desktop.overlay(false));
    }
    _changed();
  }

  Future<void> setVoice(bool enabled) async {
    voiceEnabled = enabled;
    _changed();
    if (!enabled) await _clearAudio();
    await _platform(() => desktop.volume(enabled ? volume : 0));
    _changed();
  }

  Future<void> setVolume(double value) async {
    volume = value;
    await _platform(() => desktop.volume(voiceEnabled ? volume : 0));
    _changed();
  }

  Future<void> showOverlay() async {
    await _syncNative();
    try {
      await desktop.overlay(true);
      overlayVisible = true;
      _changed();
    } catch (_) {
      error = '자막 창을 열 수 없어요. macOS 앱에서 실행해 주세요.';
      _changed();
    }
  }

  Future<void> presentOverlay() async {
    await showOverlay();
    if (overlayVisible) await _platform(desktop.hideMain);
  }

  Future<void> hideOverlay() async {
    overlayVisible = false;
    await _platform(() => desktop.overlay(false));
    _changed();
  }

  Future<void> start() async {
    if (active || _disposed) return;
    await stopMicrophoneTest();
    final request = ++_startRequest;
    await _halting;
    if (request != _startRequest || _disposed) return;
    if (apiKey.trim().isEmpty || model.trim().isEmpty) {
      error = '설정에서 Gemini API 키와 Live 모델을 입력해 주세요.';
      phase = SessionPhase.failed;
      _changed();
      return;
    }
    _previewTimer?.cancel();
    ++_sessionEpoch;
    caption.clear();
    error = '';
    phase = SessionPhase.connecting;
    _changed();
    await live.start(
      SessionConfig(
        apiKey: apiKey.trim(),
        model: model.trim(),
        first: first,
        second: second,
      ),
    );
  }

  Future<void> _capture() async {
    final epoch = _sessionEpoch;
    if (_capturing || _captureStartEpoch == epoch) return;
    _captureStartEpoch = epoch;
    try {
      _audioSubscription = desktop.audio.listen(
        (data) {
          if (!active || epoch != _sessionEpoch) return;
          live.sendAudio(data);
          _measureInput(data);
          _trackInputActivity(data.length);
          _trackLoudInput(data.length);
          _changed();
        },
        onError: (Object _) {
          if (epoch == _sessionEpoch) {
            unawaited(_fail('오디오 입력을 읽을 수 없어요. 권한과 장치를 확인해 주세요.'));
          }
        },
      );
      await desktop.selectInputDevice(inputDeviceUID);
      if (epoch != _sessionEpoch || !active) return;
      await desktop.startCapture(source.name);
      if (epoch != _sessionEpoch || !active) {
        return;
      }
      _capturing = true;
      await desktop.volume(voiceEnabled ? volume : 0);
    } on PlatformException catch (e) {
      if (epoch == _sessionEpoch) await _fail(e.message ?? '오디오 권한을 확인해 주세요.');
    } catch (_) {
      if (epoch == _sessionEpoch) {
        await _fail('오디오 엔진을 시작할 수 없어요. macOS 앱과 오디오 장치를 확인해 주세요.');
      }
    } finally {
      if (_captureStartEpoch == epoch) _captureStartEpoch = null;
    }
  }

  // Visual audio-activity cue, not speech recognition. Require sustained input
  // and hold through short pauses so the microphone does not flicker on/off.
  void _trackInputActivity(int byteCount) {
    final audible = inputLevel >= (_inputActive ? .045 : .08);
    if (audible) {
      _inputAttackMs += byteCount / 32; // PCM16 mono at 16 kHz.
      if (_inputAttackMs >= 60) _inputActive = true;
      _inputActivityTimer?.cancel();
      _inputActivityTimer = Timer(const Duration(milliseconds: 350), () {
        _inputActive = false;
        _inputAttackMs = 0;
        _changed();
      });
    } else {
      _inputAttackMs = 0;
    }
  }

  // Uncalibrated digital signal level (dBFS), not room sound pressure (dB SPL).
  // A 6 dB release band and timeout avoid flicker and handle missing packets.
  void _trackLoudInput(int byteCount) {
    final threshold = _megaphoneThresholdDbfs - (_loudInput ? 6 : 0);
    if (inputDbfs >= threshold) {
      _loudAttackMs += byteCount / 32;
      if (_loudAttackMs >= 100) _loudInput = true;
      _loudInputTimer?.cancel();
      _loudInputTimer = Timer(const Duration(milliseconds: 450), () {
        _loudInput = false;
        _loudAttackMs = 0;
        _changed();
      });
    } else {
      _loudAttackMs = 0;
    }
  }

  void _onLive(LiveEvent event) {
    if (_disposed || !active) return;
    switch (event.kind) {
      case LiveEventKind.connecting:
        phase = SessionPhase.connecting;
      case LiveEventKind.ready:
        phase = SessionPhase.listening;
        unawaited(_capture());
      case LiveEventKind.reconnecting:
        phase = SessionPhase.reconnecting;
        caption.clear();
        unawaited(_clearAudio());
      case LiveEventKind.input:
        caption.input(event.text, finished: event.finished);
      case LiveEventKind.interim:
        caption.input(event.text, provisional: true);
      case LiveEventKind.output:
        caption.output(event.text);
        phase = SessionPhase.translating;
      case LiveEventKind.audio:
        if (voiceEnabled) _playback.write(event.bytes!);
      case LiveEventKind.interrupted:
        caption.interrupt();
        phase = SessionPhase.listening;
        unawaited(_clearAudio());
      case LiveEventKind.turnComplete:
        caption.turnComplete();
        phase = SessionPhase.listening;
      case LiveEventKind.error:
        unawaited(_fail(event.text));
    }
    _changed();
  }

  Future<void> _pumpAudio() async {
    if (_pumping || !active || !voiceEnabled || _playback.length == 0) return;
    _pumping = true;
    final generation = _generation;
    final bytes = _playback.peek(1920); // 40 ms at 24 kHz PCM16.
    try {
      final accepted = await desktop.play(bytes, generation);
      if (accepted && generation == _generation) {
        _playback.discard(bytes.length);
      }
    } catch (_) {
      if (generation == _generation) {
        voiceEnabled = false;
        await _clearAudio();
        error = '음성 재생에 실패했어요. 자막 통역은 계속됩니다.';
        _changed();
      }
    } finally {
      _pumping = false;
    }
  }

  Future<void> _clearAudio() async {
    _playback.clear();
    ++_generation;
    await _platform(() => desktop.clearPlayback(_generation));
  }

  Future<void> _halt() {
    ++_startRequest;
    if (_halting != null) return _halting!;
    final work = _stopResources();
    _halting = work;
    return work.whenComplete(() => _halting = null);
  }

  Future<void> _stopResources() async {
    ++_sessionEpoch;
    testingMicrophone = false;
    _inputActivityTimer?.cancel();
    _loudInputTimer?.cancel();
    _loudInput = false;
    _loudAttackMs = 0;
    inputDbfs = -96;
    _inputActive = false;
    _inputAttackMs = 0;
    _previewTimer?.cancel();
    await live.stop();
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    await _platform(desktop.stopCapture);
    _capturing = false;
    await _clearAudio();
    inputLevel = 0;
    _changed();
  }

  Future<void> pause() async {
    phase = SessionPhase.paused;
    _changed();
    await _halt();
  }

  Future<void> stop() async {
    phase = SessionPhase.idle;
    caption.clear();
    error = '';
    _changed();
    await _halt();
  }

  Future<void> _fail(String message) async {
    phase = SessionPhase.failed;
    error = message;
    _changed();
    await _halt();
  }

  Future<void> preview() async {
    await stop();
    phase = SessionPhase.preview;
    _previewPose = 0;
    caption.input('Flutter 밋업에 오신 것을 환영합니다!', finished: true);
    caption.output('Welcome to our Flutter meetup!');
    _changed();
    var alternate = false;
    _previewTimer = Timer.periodic(const Duration(seconds: 7), (_) {
      alternate = !alternate;
      _previewPose++;
      caption.clear();
      caption.input(
        alternate
            ? 'Build for every screen from a single codebase.'
            : '만나서 반가워요!',
        finished: true,
      );
      caption.output(
        alternate ? '하나의 코드로 다양한 화면을 만듭니다.' : "It's great to meet you!",
      );
      _changed();
    });
  }

  void refresh() => _changed();
  void _changed() {
    if (_disposed) return;
    notifyListeners();
    _nativeUpdate ??= Timer(const Duration(milliseconds: 80), () {
      _nativeUpdate = null;
      unawaited(_syncNative());
    });
  }

  Future<void> _syncNative() => _platform(
    () => desktop.update({
      'original': caption.sourceText,
      'translation': caption.translation,
      'status': status,
      'pair': pairLabel,
      'active': active,
      'mascot': mascotClip,
      'mascotSkin': mascotSkin.name,
      'preview': phase == SessionPhase.preview,
    }),
  );
  Future<void> _platform(Future<void> Function() call) async {
    try {
      await call();
    } on MissingPluginException {
      /* Allows widget previews without a native host. */
    } on PlatformException {
      /* Best-effort window state / teardown. Capture errors are handled separately. */
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _pump?.cancel();
    _previewTimer?.cancel();
    _nativeUpdate?.cancel();
    _inputActivityTimer?.cancel();
    _loudInputTimer?.cancel();
    unawaited(_audioSubscription?.cancel());
    unawaited(_liveSubscription?.cancel());
    unawaited(live.dispose());
    unawaited(_platform(desktop.stopCapture));
    unawaited(_clearAudio());
    desktop.dispose();
    apiKey = '';
    super.dispose();
  }
}
