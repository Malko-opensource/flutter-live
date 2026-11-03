import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../audio/pcm_ring_buffer.dart';
import '../models.dart';

enum LiveEventKind {
  connecting,
  ready,
  reconnecting,
  input,
  interim,
  output,
  audio,
  interrupted,
  turnComplete,
  error,
}

class LiveEvent {
  const LiveEvent(
    this.kind, {
    this.text = '',
    this.bytes,
    this.finished = false,
  });
  final LiveEventKind kind;
  final String text;
  final Uint8List? bytes;
  final bool finished;
}

typedef SocketConnector = Future<WebSocket> Function(Uri uri);

class GeminiLiveClient {
  GeminiLiveClient({
    SocketConnector? connector,
    this.retryBase = const Duration(seconds: 1),
  }) : _connector = connector ?? ((uri) => WebSocket.connect(uri.toString()));
  final SocketConnector _connector;
  final Duration retryBase;
  final _events = StreamController<LiveEvent>.broadcast();
  final _input = PcmRingBuffer(16000 * 2 * 2);
  Stream<LiveEvent> get events => _events.stream;
  int get droppedInputBytes => _input.droppedBytes;
  WebSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  Timer? _retry, _handshake, _sendTimer, _stable;
  SessionConfig? _config;
  String? _resumeHandle;
  int _epoch = 0, _attempts = 0;
  bool _running = false, _ready = false;

  Future<void> start(SessionConfig config) async {
    final stopping = stop();
    final requestedEpoch = _epoch;
    await stopping;
    if (requestedEpoch != _epoch) return;
    _config = config;
    _running = true;
    _attempts = 0;
    _resumeHandle = null;
    _sendTimer = Timer.periodic(const Duration(milliseconds: 20), (_) {
      // Drain a short reconnect backlog at up to 4x, without unbounded bursts.
      for (
        var chunk = 0;
        chunk < 4 && _ready && _input.length >= 640;
        chunk++
      ) {
        _send({
          'realtimeInput': {
            'audio': {
              'mimeType': 'audio/pcm;rate=16000',
              'data': base64Encode(_input.read(640)),
            },
          },
        });
      }
    });
    await _connect();
  }

  void sendAudio(Uint8List pcm) {
    if (_running) _input.write(pcm);
  }

  Future<void> _connect() async {
    if (!_running) return;
    final epoch = ++_epoch;
    _ready = false;
    _emit(
      LiveEvent(
        _attempts == 0 ? LiveEventKind.connecting : LiveEventKind.reconnecting,
      ),
    );
    final config = _config!;
    try {
      final uri = Uri.https(
        'generativelanguage.googleapis.com',
        '/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent',
        {'key': config.apiKey},
      ).replace(scheme: 'wss');
      final pending = _connector(uri);
      // A timeout cannot cancel WebSocket.connect. Close a socket arriving late.
      unawaited(
        pending.then((socket) {
          if (!_running || epoch != _epoch) unawaited(socket.close());
        }, onError: (Object _) {}),
      );
      final socket = await pending.timeout(const Duration(seconds: 12));
      if (!_running || epoch != _epoch) {
        await socket.close();
        return;
      }
      _socket = socket;
      socket.pingInterval = const Duration(seconds: 20);
      _subscription = socket.listen(
        (data) {
          if (epoch == _epoch) _receive(data);
        },
        onError: (Object _) {
          if (epoch == _epoch) _recover();
        },
        onDone: () {
          if (epoch != _epoch) return;
          if ([1008, 1007, 1003].contains(socket.closeCode)) {
            _fail('연결이 거부됐어요. API 키, 모델 접근 권한과 설정을 확인해 주세요.');
          } else {
            _recover();
          }
        },
      );
      _send(config.setup(resumeHandle: _resumeHandle));
      _handshake = Timer(const Duration(seconds: 12), () {
        if (epoch == _epoch) _recover();
      });
    } catch (_) {
      if (epoch == _epoch) _recover();
    }
  }

  void _receive(dynamic raw) {
    try {
      final message = jsonDecode(
        raw is String ? raw : utf8.decode(raw as List<int>),
      ) as Map<String, dynamic>;
      if (message['error'] != null) {
        final code = (message['error'] as Map)['code'];
        if ([429, 500, 502, 503, 504].contains(code)) {
          _recover();
        } else {
          _fail('Gemini 요청이 거부됐어요. API 키·모델·사용 한도를 확인해 주세요.');
        }
        return;
      }
      if (message.containsKey('setupComplete')) {
        _handshake?.cancel();
        _ready = true;
        _stable?.cancel();
        _stable = Timer(const Duration(seconds: 30), () => _attempts = 0);
        _emit(const LiveEvent(LiveEventKind.ready));
      }
      final resume = message['sessionResumptionUpdate'] as Map?;
      if (resume != null) {
        _resumeHandle = resume['resumable'] == true
            ? resume['newHandle'] as String?
            : null;
      }
      final content = message['serverContent'] as Map?;
      if (content != null) {
        final interrupted = content['interrupted'] == true;
        if (interrupted) _emit(const LiveEvent(LiveEventKind.interrupted));
        for (final entry in [
          ('inputTranscription', LiveEventKind.input),
          ('interimInputTranscription', LiveEventKind.interim),
          ('outputTranscription', LiveEventKind.output),
        ]) {
          final transcript = content[entry.$1] as Map?;
          if (transcript != null &&
              !(interrupted && entry.$2 == LiveEventKind.output)) {
            _emit(
              LiveEvent(
                entry.$2,
                text: transcript['text'] as String? ?? '',
                finished: transcript['finished'] == true,
              ),
            );
          }
        }
        final parts = (content['modelTurn'] as Map?)?['parts'] as List? ?? [];
        for (final part in parts) {
          final inline = (part as Map)['inlineData'] as Map?;
          if (inline == null || interrupted) continue;
          final mime = inline['mimeType'] as String? ?? '';
          if (!mime.startsWith('audio/pcm')) continue;
          final rate = RegExp(r'rate=(\d+)').firstMatch(mime)?.group(1);
          if (rate != '24000') {
            _fail('지원되지 않는 출력 오디오 형식입니다. 24 kHz PCM 모델을 선택해 주세요.');
            return;
          }
          final pcm = base64Decode(inline['data'] as String);
          if (pcm.length.isOdd) {
            throw const FormatException('Incomplete PCM sample');
          }
          _emit(LiveEvent(LiveEventKind.audio, bytes: pcm));
        }
        if (content['turnComplete'] == true) {
          _emit(const LiveEvent(LiveEventKind.turnComplete));
        }
      }
      if (message.containsKey('goAway')) _recover();
    } catch (_) {
      _fail('서버 응답을 읽을 수 없어요. 연결을 다시 시작해 주세요.');
    }
  }

  void _send(Map<String, Object> message) {
    try {
      _socket?.add(jsonEncode(message));
    } catch (_) {
      _recover();
    }
  }

  void _recover() {
    if (!_running || _retry != null) return;
    if (_attempts >= 6) {
      _fail('연결을 복구하지 못했어요. 네트워크를 확인하고 다시 시작해 주세요.');
      return;
    }
    ++_epoch;
    _ready = false;
    _handshake?.cancel();
    _stable?.cancel();
    unawaited(_subscription?.cancel());
    unawaited(_socket?.close());
    _socket = null;
    _emit(const LiveEvent(LiveEventKind.reconnecting));
    final delay = min(16000, retryBase.inMilliseconds * (1 << _attempts++));
    _retry = Timer(Duration(milliseconds: delay + Random().nextInt(250)), () {
      _retry = null;
      unawaited(_connect());
    });
  }

  void _fail(String message) {
    unawaited(stop());
    _emit(LiveEvent(LiveEventKind.error, text: message));
  }

  void _emit(LiveEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  Future<void> stop() async {
    _running = false;
    _ready = false;
    ++_epoch;
    _retry?.cancel();
    _retry = null;
    _handshake?.cancel();
    _stable?.cancel();
    _sendTimer?.cancel();
    _input.clear();
    final sub = _subscription;
    _subscription = null;
    final socket = _socket;
    _socket = null;
    await sub?.cancel();
    unawaited(socket?.close());
  }

  Future<void> dispose() async {
    await stop();
    await _events.close();
  }
}
