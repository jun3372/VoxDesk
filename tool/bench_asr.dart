// ASR 解码基准：测量 FireRedAsr2 int8 在不同线程数 / worker 数下的
// 解码耗时，用于确定 device_tuning.dart 的并行参数（worker 数与线程数
// 的取舍依据）。运行方式：
//
//   dart run tool/bench_asr.dart serial     # 1 个 recognizer，线程数扫描
//   dart run tool/bench_asr.dart parallel   # 2 个 recognizer × 4 线程并发
//   dart run tool/bench_asr.dart            # 两者都跑
//
// 原生库来自 pub 缓存的 sherpa_onnx_macos 包，模型取 ./models 下已下载
// 的 FireRedAsr2；音频为 12s 合成「语音状」信号（识别结果无意义，只看
// 耗时，各配置输入相同，横向可比）。
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

const pubCache =
    '/Users/jun/.pub-cache/hosted/pub.dev/sherpa_onnx_macos-1.13.8/macos';
const modelDir = 'models/sherpa-onnx-fire-red-asr2-zh_en-int8-2026-02-26';
const segmentSec = 12.0;

sherpa.OfflineRecognizer buildRecognizer(int numThreads) {
  final config = sherpa.OfflineRecognizerConfig(
    model: sherpa.OfflineModelConfig(
      fireRedAsr: sherpa.OfflineFireRedAsrModelConfig(
        encoder: '$modelDir/encoder.int8.onnx',
        decoder: '$modelDir/decoder.int8.onnx',
      ),
      tokens: '$modelDir/tokens.txt',
      numThreads: numThreads,
      debug: false,
      provider: 'cpu',
    ),
  );
  return sherpa.OfflineRecognizer(config);
}

/// 合成语音状音频：syllable 节奏的幅度包络调制谐波 + 噪声。
Float32List synthSamples(int sampleRate, double seconds, int seed) {
  final n = (sampleRate * seconds).toInt();
  final rng = Random(seed);
  final out = Float32List(n);
  var phase = 0.0;
  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    final syllable = 0.55 + 0.45 * sin(2 * pi * 3.7 * t);
    final f0 = 130 + 40 * sin(2 * pi * 0.9 * t);
    phase += 2 * pi * f0 / sampleRate;
    var v = 0.0;
    for (var h = 1; h <= 8; h++) {
      v += sin(phase * h) / h;
    }
    v = v * 0.5 + (rng.nextDouble() * 2 - 1) * 0.35;
    out[i] = (v * syllable * 0.35).clamp(-1.0, 1.0);
  }
  return out;
}

double decodeOnce(sherpa.OfflineRecognizer rec, Float32List samples) {
  final sw = Stopwatch()..start();
  final stream = rec.createStream();
  stream.acceptWaveform(samples: samples, sampleRate: 16000);
  rec.decode(stream);
  rec.getResult(stream).text;
  stream.free();
  return sw.elapsedMicroseconds / 1e6;
}

/// 1 个 recognizer，线程数扫描：热身 1 次 + 计时 3 次取中位数。
Future<void> benchSerial() async {
  sherpa.initBindings(pubCache);
  final samples = synthSamples(16000, segmentSec, 42);
  for (final threads in [2, 4, 6, 8]) {
    final rec = buildRecognizer(threads);
    decodeOnce(rec, samples); // 热身
    final times = [for (var i = 0; i < 3; i++) decodeOnce(rec, samples)]
      ..sort();
    final med = times[1];
    final detail = times.map((t) => t.toStringAsFixed(2)).join(', ');
    stdout.writeln('serial threads=$threads  median=${med.toStringAsFixed(2)}s (x3: $detail)');
    rec.free();
  }
}

/// 2 个 recognizer × 4 线程，在两个独立 Isolate 中同时各解码一段，
/// 模拟 AsrEnginePool 的并发模式；报告单段耗时与总墙钟时间。
Future<void> benchParallel2() async {
  Future<({double decodeSec, double wallSec})> one(int seed) {
    final sw = Stopwatch()..start();
    return Isolate.run(() {
      sherpa.initBindings(pubCache);
      final rec = buildRecognizer(4);
      final samples = synthSamples(16000, segmentSec, seed);
      final t = decodeOnce(rec, samples);
      rec.free();
      return t;
    }).then((t) => (decodeSec: t, wallSec: sw.elapsedMicroseconds / 1e6));
  }

  final results = await Future.wait([one(42), one(43)]);
  final wall = results.map((r) => r.wallSec).reduce(max);
  final decodes = results.map((r) => r.decodeSec.toStringAsFixed(2)).join(', ');
  stdout.writeln('parallel 2x4  decode=[$decodes]s  wall=${wall.toStringAsFixed(2)}s');
}

Future<void> main(List<String> args) async {
  final mode = args.isEmpty ? 'all' : args.first;
  if (mode == 'serial' || mode == 'all') await benchSerial();
  if (mode == 'parallel' || mode == 'all') await benchParallel2();
}
