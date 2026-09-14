import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:voxdesk/services/recorder_service.dart';

/// 生成 440Hz 正弦波块（parecord 默认约 100ms 一块，1600 采样）。
Float32List sineBlock(double amplitude, [int samples = 1600]) {
  final out = Float32List(samples);
  for (var i = 0; i < samples; i++) {
    out[i] = amplitude * sin(2 * pi * 440 * i / MicAgc.sampleRate);
  }
  return out;
}

double rmsOf(Float32List s) {
  var sumSq = 0.0;
  for (final v in s) {
    sumSq += v * v;
  }
  return sqrt(sumSq / s.length);
}

void main() {
  group('MicAgc', () {
    test('偏低电平被抬升到目标区间附近', () {
      final agc = MicAgc();
      // 采集电平 RMS≈0.02（-34dBFS），连续喂 3 秒等待增益收敛
      Float32List block = sineBlock(0.028);
      for (var i = 0; i < 30; i++) {
        block = sineBlock(0.028);
        agc.process(block);
      }
      expect(agc.gain, greaterThan(1.0));
      expect(rmsOf(block), inExclusiveRange(0.08, 0.18));
    });

    test('电平正常的输入不衰减、不被修改', () {
      final agc = MicAgc();
      final input = sineBlock(0.7);
      for (var i = 0; i < 30; i++) {
        final block = sineBlock(0.7);
        agc.process(block);
        for (var j = 0; j < block.length; j++) {
          expect(block[j], input[j]);
        }
      }
      expect(agc.gain, 1.0);
    });

    test('纯静音段增益保持 1，不追底噪', () {
      final agc = MicAgc();
      for (var i = 0; i < 50; i++) {
        agc.process(Float32List(1600));
      }
      expect(agc.gain, 1.0);
    });

    test('极低电平增益封顶在 maxGain', () {
      final agc = MicAgc();
      Float32List block = sineBlock(0.006);
      for (var i = 0; i < 50; i++) {
        block = sineBlock(0.006);
        agc.process(block);
      }
      expect(agc.gain, inExclusiveRange(8.0, agc.maxGain + 0.01));
      for (final v in block) {
        expect(v.abs(), lessThanOrEqualTo(0.98));
      }
    });

    test('块长不影响收敛结果（时间常数按块长折算）', () {
      // 同一段弱信号分别按 100ms 与 20ms 分块处理，最终增益应一致
      double gainAfter(int blockSize) {
        final agc = MicAgc();
        for (var i = 0; i < 150; i++) {
          agc.process(sineBlock(0.028, blockSize));
        }
        return agc.gain;
      }

      expect(gainAfter(1600), closeTo(gainAfter(320), 0.3));
    });

    test('放大的块峰值不越过 ±0.98', () {
      final agc = MicAgc();
      // 高增益场景下混入瞬时尖峰
      for (var i = 0; i < 30; i++) {
        final block = sineBlock(0.028);
        if (i == 25) block[800] = 0.5;
        agc.process(block);
        for (final v in block) {
          expect(v.abs(), lessThanOrEqualTo(0.9800001));
        }
      }
    });
  });
}
