import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_live/src/audio/pcm_ring_buffer.dart';
import 'package:flutter_live/src/models.dart';

void main() {
  test('PCM ring wraps and discards oldest complete samples on overflow', () {
    final ring = PcmRingBuffer(8);
    ring.write(Uint8List.fromList([1, 2, 3, 4, 5, 6]));
    expect(ring.read(4), [1, 2, 3, 4]);
    ring.write(Uint8List.fromList([7, 8, 9, 10, 11, 12, 13, 14]));
    expect(ring.droppedBytes, 2);
    expect(ring.read(100), [7, 8, 9, 10, 11, 12, 13, 14]);
    expect(ring.length, 0);
    expect(() => ring.write(Uint8List(3)), throwsArgumentError);
  });
  test('PCM overflow stays bounded during a long network outage', () {
    final ring = PcmRingBuffer(64000);
    for (var i = 0; i < 500; i++) {
      ring.write(Uint8List(640));
    }
    expect(ring.length, 64000);
    expect(ring.droppedBytes, 256000);
    ring.clear();
    expect(ring.length, 0);
  });
  test(
    'Current captions append deltas, replace interim and clear at next turn',
    () {
      final caption = CurrentCaption();
      caption.input('안녕');
      caption.input('하세요', finished: true);
      caption.output('Hello');
      caption.output(' there');
      expect(caption.original, '안녕하세요');
      expect(caption.translation, 'Hello there');
      caption.turnComplete();
      caption.input('다음 발', provisional: true);
      caption.input('다음 발화', provisional: true);
      expect(caption.sourceText, '다음 발화');
      caption.input('다음 발화', finished: true);
      caption.output('Next');
      expect(caption.sourceText, '다음 발화');
      expect(caption.translation, 'Next');
      caption.interrupt();
      expect(caption.translation, '');
      caption.clear();
      expect(caption.sourceText, '');
    },
  );
  test(
    'Setup requests both transcriptions and a constrained language pair',
    () {
      final setup = SessionConfig(
        apiKey: 'secret',
        model: 'test-model',
        first: Language.values[0],
        second: Language.values[1],
      ).setup(resumeHandle: 'resume');
      expect(setup.toString(), isNot(contains('secret')));
      expect((setup['setup'] as Map)['sessionResumption'], {
        'handle': 'resume',
      });
      expect((setup['setup'] as Map)['inputAudioTranscription'], isEmpty);
      expect((setup['setup'] as Map)['outputAudioTranscription'], isEmpty);
      expect(setup.toString(), contains('Korean'));
      expect(setup.toString(), contains('English'));
    },
  );
}
