import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:voxdesk/services/wav_io.dart';

/// 构造最小 PCM16 WAV 字节（RIFF + fmt + data）。
Uint8List _wrapWav(Uint8List data, int sampleRate, int channels) {
  Uint8List chunk(String id, Uint8List body) {
    final head = ByteData(8)..setUint32(4, body.length, Endian.little);
    final b = head.buffer.asUint8List();
    b.setRange(0, 4, id.codeUnits);
    final bb = BytesBuilder()
      ..add(b)
      ..add(body);
    if (body.length.isOdd) bb.addByte(0); // RIFF 块按偶数字节对齐
    return bb.toBytes();
  }

  final fmt = ByteData(16)
    ..setUint16(0, 1, Endian.little)
    ..setUint16(2, channels, Endian.little)
    ..setUint32(4, sampleRate, Endian.little)
    ..setUint32(8, sampleRate * channels * 2, Endian.little)
    ..setUint16(12, channels * 2, Endian.little)
    ..setUint16(14, 16, Endian.little);
  final fmtChunk = chunk('fmt ', fmt.buffer.asUint8List());
  final dataChunk = chunk('data', data);

  final head = ByteData(12)
    ..setUint32(4, 4 + fmtChunk.length + dataChunk.length, Endian.little);
  final headBytes = head.buffer.asUint8List();
  headBytes.setRange(0, 4, 'RIFF'.codeUnits);
  headBytes.setRange(8, 12, 'WAVE'.codeUnits);
  return (BytesBuilder()
        ..add(headBytes)
        ..add(fmtChunk)
        ..add(dataChunk))
      .toBytes();
}

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

    test('PCM16 批量视图与逐样本 ByteData 结果一致', () {
      // 构造覆盖正负极值与随机值的 PCM16 数据
      final rng = Random(7);
      final n = 1000;
      final ints = Int16List(n);
      ints[0] = -32768;
      ints[1] = 32767;
      for (var i = 2; i < n; i++) {
        ints[i] = rng.nextInt(65536) - 32768;
      }
      final data = ints.buffer.asUint8List();

      // 参照：逐样本 little-endian 读取
      final dv = ByteData.sublistView(data);
      final expected = Float32List(n);
      for (var i = 0; i < n; i++) {
        expected[i] = dv.getInt16(i * 2, Endian.little) / 32768.0;
      }

      final wav = parseWav(_wrapWav(data, 16000, 1));
      expect(wav.samples.length, n);
      for (var i = 0; i < n; i++) {
        expect(wav.samples[i], expected[i]);
      }
    });

    test('data 块走零拷贝视图且结果一致', () {
      // parseWav 对 data 块使用 sublistView，验证多字节样本不被错位
      final ints = Int16List.fromList([100, -200, 300, -32768, 32767]);
      final data = ints.buffer.asUint8List();
      final wav = parseWav(_wrapWav(data, 16000, 1));
      expect(wav.samples.length, 5);
      for (var i = 0; i < 5; i++) {
        expect(wav.samples[i], closeTo(ints[i] / 32768.0, 1e-9));
      }
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
