import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:audio_decoder/audio_decoder.dart';

import 'wav_io.dart';

/// 解码后的音频（16kHz 单声道）。
class DecodedAudio {
  const DecodedAudio({required this.samples, required this.durationSec});

  final Float32List samples;
  final double durationSec;
}

/// 音频文件解码服务：任意支持格式（WAV/MP3/M4A/FLAC/OGG…）→ 16kHz 单声道 Float32。
///
/// WAV 直接本地解析（快、无外部依赖）；其余格式通过平台原生解码器
/// （audio_decoder）转成 16kHz/单声道/PCM16 的临时 WAV 再解析。
/// Linux 下依赖系统 GStreamer（见 docs/MODELS.md）。
class AudioDecodeService {
  static const Set<String> supportedExtensions =
      AudioDecoder.supportedExtensions;

  static bool isSupported(String path) {
    // WAV/WAVE 由本地 parseWav 解析，不在插件扩展名清单里；
    // 清单中的扩展名带点前缀（如 '.mp3'），用 endsWith 匹配
    final lower = path.toLowerCase();
    if (lower.endsWith('.wav') || lower.endsWith('.wave')) return true;
    return supportedExtensions.any(lower.endsWith);
  }

  /// 解析 + 混音/重采样是纯 Dart 逐样本计算，长音频可达数亿样本，
  /// 挪到 isolate 避免阻塞 UI 线程。
  static Future<Float32List> _parseAndConvert(Uint8List bytes) {
    return Isolate.run(() {
      final wav = parseWav(bytes);
      return toMono16k(wav.samples, wav.sampleRate, wav.channels);
    });
  }

  static Future<DecodedAudio> decodeToMono16k(String path) async {
    final file = File(path);
    if (!file.existsSync()) throw Exception('音频文件不存在: $path');

    if (path.toLowerCase().endsWith('.wav')) {
      try {
        final samples = await _parseAndConvert(await file.readAsBytes());
        return DecodedAudio(
          samples: samples,
          durationSec: samples.length / 16000.0,
        );
      } on FormatException {
        // 非标准 WAV（如压缩编码），走通用解码路径
      }
    }

    final tmp =
        '${Directory.systemTemp.path}'
        '/voxdesk_${DateTime.now().millisecondsSinceEpoch}.wav';
    try {
      await AudioDecoder.convertToWav(
        path,
        tmp,
        sampleRate: 16000,
        channels: 1,
        bitDepth: 16,
      );
      final samples = await _parseAndConvert(await File(tmp).readAsBytes());
      return DecodedAudio(
        samples: samples,
        durationSec: samples.length / 16000.0,
      );
    } finally {
      try {
        final f = File(tmp);
        if (f.existsSync()) await f.delete();
      } catch (_) {}
    }
  }

  /// 计算波形峰位（用于转写完成后的波形图），返回 0..1 归一化幅度。
  static Future<List<double>> computeWaveform(
    String path, {
    int buckets = 240,
  }) async {
    try {
      final wave = await AudioDecoder.getWaveform(
        path,
        numberOfSamples: buckets,
      );
      return wave;
    } catch (_) {
      return const [];
    }
  }

  /// 从已解码采样计算波形峰位（避免二次解码）。
  static List<double> waveformFromSamples(
    Float32List samples, {
    int buckets = 240,
  }) {
    if (samples.isEmpty) return const [];
    final per = samples.length / buckets;
    final out = List<double>.filled(buckets, 0);
    var max = 0.0;
    for (var b = 0; b < buckets; b++) {
      final start = (b * per).floor();
      final end = (((b + 1) * per).floor()).clamp(start + 1, samples.length);
      var peak = 0.0;
      for (var i = start; i < end; i++) {
        final v = samples[i].abs();
        if (v > peak) peak = v;
      }
      out[b] = peak;
      if (peak > max) max = peak;
    }
    if (max > 0) {
      for (var i = 0; i < out.length; i++) {
        out[i] = out[i] / max;
      }
    }
    return out;
  }
}
