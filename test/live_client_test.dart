import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_live/src/live/gemini_live_client.dart';
import 'package:flutter_live/src/models.dart';

final config = SessionConfig(
  apiKey: 'not-a-real-key',
  model: 'test',
  first: Language.values[0],
  second: Language.values[1],
);
Future<void> eventually(bool Function() condition) async {
  for (var i = 0; i < 200; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Condition did not become true');
}

void main() {
  late HttpServer server;
  late GeminiLiveClient client;
  late List<WebSocket> peers;
  late List<Map<String, dynamic>> received;
  late List<LiveEvent> events;
  setUp(() async {
    peers = [];
    received = [];
    events = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final peer = await WebSocketTransformer.upgrade(request);
      peers.add(peer);
      peer.listen((data) {
        received.add(jsonDecode(data as String) as Map<String, dynamic>);
      });
    });
    client = GeminiLiveClient(
      connector: (_) => WebSocket.connect('ws://127.0.0.1:${server.port}'),
      retryBase: const Duration(milliseconds: 20),
    );
    client.events.listen(events.add);
  });
  tearDown(() async {
    await client.dispose();
    for (final peer in peers) {
      unawaited(peer.close());
    }
    await server.close(force: true);
  });
  test('setup gates input; all audio parts and transcriptions in one frame survive', () async {
    await client.start(config);
    client.sendAudio(Uint8List(640));
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(received.length, 1);
    expect(received.single.containsKey('setup'), true);
    peers.single.add(jsonEncode({'setupComplete': {}}));
    await eventually(() => received.length == 2);
    expect(
      (received[1]['realtimeInput'] as Map)['audio']['mimeType'],
      'audio/pcm;rate=16000',
    );
    peers.single.add(
      jsonEncode({
        'serverContent': {
          'inputTranscription': {'text': '안녕하세요', 'finished': true},
          'outputTranscription': {'text': 'Hello'},
          'modelTurn': {
            'parts': [
              {
                'inlineData': {
                  'mimeType': 'audio/pcm;rate=24000',
                  'data': base64Encode([1, 2]),
                },
              },
              {
                'inlineData': {
                  'mimeType': 'audio/pcm;rate=24000',
                  'data': base64Encode([3, 4]),
                },
              },
            ],
          },
          'turnComplete': true,
        },
      }),
    );
    await eventually(
      () => events.any((e) => e.kind == LiveEventKind.turnComplete),
    );
    expect(
      events
          .where((e) => e.kind == LiveEventKind.audio)
          .map((e) => e.bytes!.toList()),
      [
        [1, 2],
        [3, 4],
      ],
    );
    expect(
      events.any((e) => e.kind == LiveEventKind.input && e.text == '안녕하세요'),
      true,
    );
    expect(
      events.any((e) => e.kind == LiveEventKind.output && e.text == 'Hello'),
      true,
    );
  });
  test('interrupt discards audio carried in the same server event', () async {
    await client.start(config);
    peers.single.add(
      jsonEncode({
        'serverContent': {
          'interrupted': true,
          'modelTurn': {
            'parts': [
              {
                'inlineData': {
                  'mimeType': 'audio/pcm;rate=24000',
                  'data': base64Encode([0, 0]),
                },
              },
            ],
          },
        },
      }),
    );
    await eventually(
      () => events.any((e) => e.kind == LiveEventKind.interrupted),
    );
    expect(events.where((e) => e.kind == LiveEventKind.audio), isEmpty);
  });
  test(
    'goAway resumes with handle; explicit stop cancels reconnection',
    () async {
      await client.start(config);
      peers.single.add(jsonEncode({'setupComplete': {}}));
      peers.single.add(
        jsonEncode({
          'sessionResumptionUpdate': {
            'resumable': true,
            'newHandle': 'resume-token',
          },
        }),
      );
      peers.single.add(
        jsonEncode({
          'goAway': {'timeLeft': '1s'},
        }),
      );
      await eventually(
        () => received.where((m) => m.containsKey('setup')).length == 2,
      );
      expect((received.last['setup'] as Map)['sessionResumption'], {
        'handle': 'resume-token',
      });
      await client.stop();
      final count = peers.length;
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(peers.length, count);
    },
  );
  test(
    'fatal server error stops and does not expose raw error or key',
    () async {
      await client.start(config);
      peers.single.add(
        jsonEncode({
          'error': {'code': 403, 'message': 'private not-a-real-key'},
        }),
      );
      await eventually(() => events.any((e) => e.kind == LiveEventKind.error));
      expect(events.last.text, isNot(contains('not-a-real-key')));
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(peers.length, 1);
    },
  );
}
