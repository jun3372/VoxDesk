import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:voxdesk/services/wav_io.dart';

void main() {
  group('WAV 写入与解析', () {
    test('writeWav → parseWav 往返一致', () {
      final samples = Float32List.fromList([0.0, 0.5, -0.5, 1.0, -1.0]);
      final bytes = writeWav(samples, 16000, 1);

      final wav = parseWav(bytes);
      expect(wav.sampleRate, 16000);
      expect(wav.channels, 1);
      expect(wav.samples.length, samples.length);
      for (var i = 0; i < samples.length; i++) {
        expect(wav.samples[i], closeTo(samples[i], 1 / 32768));
      }
    });

    test('非 WAV 字节抛 FormatException', () {
      expect(() => parseWav(Uint8List.fromList([1, 2, 3])),
          throwsFormatException);
    });
  });

  group('toMono16k', () {
    test('已经是 16k 单声道时原样返回', () {
      final input = Float32List.fromList([0.1, 0.2, 0.3]);
      expect(identical(toMono16k(input, 16000, 1), input), isTrue);
    });

    test('立体声混音为单声道', () {
      final input = Float32List.fromList([1.0, 0.0, -1.0, 0.0]);
      final mono = toMono16k(input, 16000, 2);
      expect(mono.length, 2);
      expect(mono[0], closeTo(0.5, 1e-9));
      expect(mono[1], closeTo(-0.5, 1e-9));
    });

    test('重采样改变长度', () {
      final input = Float32List(32000); // 2 秒 @32k
      final out = toMono16k(input, 32000, 1);
      expect(out.length, 16000); // 1 秒 @16k
    });
  });
}
