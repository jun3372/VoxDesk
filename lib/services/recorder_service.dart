import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:record/record.dart';

/// 麦克风采集服务：16kHz / 单声道 / PCM16 → Float32 采样回调。
class RecorderService {
  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _sub;

  Future<void> start(void Function(Float32List samples) onSamples) async {
    await stop();
    final rec = _recorder = AudioRecorder();
    if (!await rec.hasPermission()) {
      throw Exception('麦克风权限被拒绝，请在系统设置中允许访问麦克风');
    }
    final agc = MicAgc();
    final stream = await rec.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: MicAgc.sampleRate,
        numChannels: 1,
      ),
    );
    _sub = stream.listen((chunk) {
      final n = chunk.lengthInBytes ~/ 2;
      if (n == 0) return;
      // 分片的 offsetInBytes 可能不是偶数，ByteData 无元素对齐要求，逐样本读取更安全
      final data = chunk.buffer.asByteData(chunk.offsetInBytes, n * 2);
      final f32 = Float32List(n);
      for (var i = 0; i < n; i++) {
        f32[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
      }
      // Linux 目标机（云桌面/精简 UOS）麦克风电平偏低且波动大，
      // 采集后统一做电平归一，VAD 触发与识别质量才稳定
      agc.process(f32);
      onSamples(f32);
    });
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    final rec = _recorder;
    _recorder = null;
    if (rec != null) {
      try {
        if (await rec.isRecording()) await rec.stop();
      } finally {
        await rec.dispose();
      }
    }
  }
}

/// 轻量软件 AGC：把偏低的麦克风电平抬到目标区间，仅放大、不衰减。
///
/// 采集链路（Linux 端经 parecord，PulseAudio/PipeWire）的系统级
/// AGC/降噪属性行为随发行版差异很大且不可依赖，电平归一在应用内做：
/// 慢速包络估计当前语音电平，增益平滑收敛到目标 RMS，块内峰值兜底限幅。
/// 对电平正常的输入增益收敛到 1，近似无操作。
class MicAgc {
  MicAgc({
    this.targetRms = 0.12,
    this.maxGain = 10.0,
    this.noiseFloorRms = 0.004,
  });

  /// 与 RecordConfig 的采集采样率一致。
  static const int sampleRate = 16000;

  /// 目标语音电平（RMS，约 -18 dBFS）。
  final double targetRms;

  /// 增益上限（+20 dB），限制底噪被放大的程度。
  final double maxGain;

  /// 包络低于该值视为静音/底噪，增益保持不动（不追底噪）。
  final double noiseFloorRms;

  double _gain = 1;
  double _envelope = 0;

  /// 当前增益（测试/调参观察用）。
  double get gain => _gain;

  /// 就地归一化一段采样。
  void process(Float32List samples) {
    if (samples.isEmpty) return;
    final dt = samples.length / sampleRate;

    var sumSq = 0.0;
    var peak = 0.0;
    for (var i = 0; i < samples.length; i++) {
      final v = samples[i];
      sumSq += v * v;
      final a = v.abs();
      if (a > peak) peak = a;
    }
    final rms = sqrt(sumSq / samples.length);

    // 电平包络：上冲快（~0.1s）、回落慢（~0.4s），句子内稳住电平估计
    _envelope += _step(dt, rms > _envelope ? 0.1 : 0.4) * (rms - _envelope);

    // 低于噪声门限时增益保持，避免字间底噪被逐渐泵起
    if (_envelope >= noiseFloorRms) {
      final desired = (targetRms / _envelope).clamp(1.0, maxGain);
      // 增益平滑：抬升快（~0.25s）、回落慢（~0.6s）
      _gain += _step(dt, desired > _gain ? 0.25 : 0.6) * (desired - _gain);
    }

    // 只放大不衰减：增益为 1 时不触碰采样；放大时块内峰值兜底，
    // 无论增益多大，采样不允许越过 ±0.98（防瞬态削波）
    var g = _gain;
    if (g > 1) {
      if (peak > 0 && g * peak > 0.98) g = 0.98 / peak;
      for (var i = 0; i < samples.length; i++) {
        samples[i] *= g;
      }
    }
  }

  /// 一阶平滑步进系数（时间常数 [tau] 秒，块长 [dt] 秒）。
  static double _step(double dt, double tau) => 1 - exp(-dt / tau);
}
