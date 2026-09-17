import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// 语音段来源抽象：转写流水线（transcribe_pipeline.dart）依赖该接口，
/// 便于测试时注入假 VAD。
abstract class SegmentSource {
  void acceptWaveform(Float32List window);

  /// 是否已有完整的语音段可取。
  bool get hasSegment;

  /// 当前语音段（须先确认 [hasSegment]）。
  ({Float32List samples, int start}) front();

  void pop();

  /// 结束输入流时冲出剩余语音段。
  void flush();
}

/// Silero VAD 封装（16kHz 输入）。
///
/// 语音段阈值/时长参数与 sherpa-onnx 官方 `vad-with-offline-asr` 示例一致，
/// maxSpeechDuration 放宽到 15s 以减少句子被截断。
class VadEngine implements SegmentSource {
  sherpa.VoiceActivityDetector? _vad;

  static const int sampleRate = 16000;

  void load(String sileroModelPath) {
    free();
    final config = sherpa.VadModelConfig(
      sileroVad: sherpa.SileroVadModelConfig(
        model: sileroModelPath,
        threshold: 0.5,
        minSilenceDuration: 0.5,
        minSpeechDuration: 0.25,
        windowSize: 512,
        maxSpeechDuration: 15,
      ),
      sampleRate: sampleRate,
      numThreads: 1,
      debug: false,
    );
    _vad = sherpa.VoiceActivityDetector(
      config: config,
      bufferSizeInSeconds: 120,
    );
  }

  bool get loaded => _vad != null;

  @override
  void acceptWaveform(Float32List samples) => _vad!.acceptWaveform(samples);

  @override
  bool get hasSegment => !(_vad?.isEmpty() ?? true);

  @override
  ({Float32List samples, int start}) front() {
    final s = _vad!.front();
    return (samples: s.samples, start: s.start);
  }

  @override
  void pop() => _vad!.pop();

  @override
  void flush() => _vad!.flush();

  void reset() => _vad?.reset();

  void free() {
    _vad?.free();
    _vad = null;
  }
}

/// 将任意长度的采样流按 VAD 窗口（512 采样）切块喂入。
class VadWindowFeeder {
  VadWindowFeeder(this._onWindow, [this._windowSize = 512]);

  final void Function(Float32List window) _onWindow;
  final int _windowSize;

  final List<double> _carry = [];

  void feed(Float32List samples) {
    var offset = 0;
    while (_carry.isNotEmpty &&
        _carry.length + (samples.length - offset) >= _windowSize) {
      final need = _windowSize - _carry.length;
      for (var i = 0; i < need; i++) {
        _carry.add(samples[offset + i]);
      }
      offset += need;
      _onWindow(Float32List.fromList(_carry));
      _carry.clear();
    }
    while (offset + _windowSize <= samples.length) {
      _onWindow(Float32List.sublistView(samples, offset, offset + _windowSize));
      offset += _windowSize;
    }
    for (; offset < samples.length; offset++) {
      _carry.add(samples[offset]);
    }
  }
}
