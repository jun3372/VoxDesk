import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:voxdesk/services/wav_io.dart';
import 'package:voxdesk/services/wav_stream_writer.dart';

void main() {
  group('WavStreamWriter 流式落盘', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('voxdesk_wav_stream_');
    });

    tearDown(() async {
      if (tmp.existsSync()) await tmp.delete(recursive: true);
    });

    test('append → finalize 后与 writeWav 解析结果一致', () async {
      final path = '${tmp.path}/session.wav';
      final writer = await WavStreamWriter.open(path);
      final a = Float32List.fromList([0.0, 0.5, -0.5, 1.0, -1.0]);
      final b = Float32List.fromList([0.25, -0.25]);
      writer.append(a);
      writer.append(b);
      expect(writer.sampleCount, 7);
      await writer.finalize();

      final wav = parseWav(await File(path).readAsBytes());
      expect(wav.sampleRate, 16000);
      expect(wav.channels, 1);
      expect(wav.samples.length, 7);
      final expected = [...a, ...b];
      for (var i = 0; i < expected.length; i++) {
        expect(wav.samples[i], closeTo(expected[i], 2 / 32768));
      }
    });

    test('未 finalize 的半成品文件也能读出已写入内容（增量分离场景）', () async {
      final path = '${tmp.path}/session.wav';
      final writer = await WavStreamWriter.open(path);
      writer.append(Float32List.fromList([0.1, -0.2, 0.3]));
      await writer.flush();

      final wav = parseWav(await File(path).readAsBytes());
      expect(wav.samples.length, 3);
      expect(wav.samples[0], closeTo(0.1, 1 / 32768));

      await writer.finalize();
      // finalize 后内容不变
      final wav2 = parseWav(await File(path).readAsBytes());
      expect(wav2.samples.length, 3);
    });

    test('abort 删除文件', () async {
      final path = '${tmp.path}/session.wav';
      final writer = await WavStreamWriter.open(path);
      writer.append(Float32List.fromList([0.5]));
      await writer.abort();
      expect(File(path).existsSync(), isFalse);
    });

    test('readWavStreamed 读取 finalize 后的文件与 writeWav 一致', () async {
      final path = '${tmp.path}/session.wav';
      final expected = Float32List.fromList(
        List.generate(100000, (i) => (i % 200 - 100) / 100.0),
      );
      await File(path).writeAsBytes(writeWav(expected, 16000, 1));

      final wav = await readWavStreamed(path);
      expect(wav.sampleRate, 16000);
      expect(wav.channels, 1);
      expect(wav.samples.length, expected.length);
      for (var i = 0; i < expected.length; i += 997) {
        expect(wav.samples[i], closeTo(expected[i], 2 / 32768));
      }
    });

    test('readWavStreamed 读取未回填头部的半成品文件', () async {
      final path = '${tmp.path}/session.wav';
      final writer = await WavStreamWriter.open(path);
      final expected = Float32List.fromList([0.1, -0.2, 0.3, 0.9]);
      writer.append(expected);
      await writer.flush();

      // 头部尺寸仍是占位大值，按文件实际剩余读取
      final wav = await readWavStreamed(path);
      expect(wav.samples.length, expected.length);
      for (var i = 0; i < expected.length; i++) {
        expect(wav.samples[i], closeTo(expected[i], 2 / 32768));
      }
      await writer.abort();
    });
  });
}
