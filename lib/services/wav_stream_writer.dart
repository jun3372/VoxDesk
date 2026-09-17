import 'dart:io';
import 'dart:typed_data';

/// 流式 WAV（16kHz 单声道 PCM16）写入器：录音分片边录边落盘，
/// 避免整段会话驻留内存。
///
/// 头部两个尺寸字段先填占位大值，[finalize] 时回填真实值。
/// 录制中途的半成品文件仍可被 `parseWav` 读出已有内容
/// （data 块越界有 clamp），增量说话人分离可直接读盘。
class WavStreamWriter {
  WavStreamWriter._(this._file, this._sink);

  static const int sampleRate = 16000;

  /// 头部尺寸占位值（偶数，保证 data 块对齐规则下解析稳定）。
  static const int _placeholderSize = 0x7FFFFFFE;

  final File _file;
  final IOSink _sink;

  /// 已写入的采样数。
  int sampleCount = 0;

  static Future<WavStreamWriter> open(String path) async {
    final file = File(path);
    final sink = file.openWrite();
    sink.add(_header());
    return WavStreamWriter._(file, sink);
  }

  /// 追加一段采样（归一化 -1.0..1.0 转 int16 LE）。
  /// IOSink 内部保序排队，同步入队即可，错误在 [finalize] 时抛出。
  void append(Float32List samples) {
    if (samples.isEmpty) return;
    final pcm = ByteData(samples.length * 2);
    for (var i = 0; i < samples.length; i++) {
      final v = samples[i].clamp(-1.0, 1.0);
      pcm.setInt16(i * 2, (v * 32767).round(), Endian.little);
    }
    _sink.add(pcm.buffer.asUint8List());
    sampleCount += samples.length;
  }

  /// 把缓冲数据冲刷到磁盘（录制中途读盘前调用）。
  Future<void> flush() => _sink.flush();

  /// 收尾：关闭写入流并回填头部真实尺寸。
  Future<void> finalize() async {
    await _sink.flush();
    await _sink.close();
    final dataSize = sampleCount * 2;
    final raf = await _file.open(mode: FileMode.writeOnlyAppend);
    try {
      final patch = ByteData(4);
      await raf.setPosition(4);
      patch.setUint32(0, 36 + dataSize, Endian.little);
      await raf.writeFrom(patch.buffer.asUint8List());
      await raf.setPosition(40);
      patch.setUint32(0, dataSize, Endian.little);
      await raf.writeFrom(patch.buffer.asUint8List());
    } finally {
      await raf.close();
    }
  }

  /// 放弃本次写入：尽力关闭并删除文件。
  Future<void> abort() async {
    try {
      await _sink.close();
    } catch (_) {}
    try {
      if (_file.existsSync()) await _file.delete();
    } catch (_) {}
  }

  /// 44 字节 PCM16 WAV 头（尺寸字段为占位值）。
  static Uint8List _header() {
    final header = ByteData(44);

    void putStr(int offset, String s) {
      for (var i = 0; i < s.length; i++) {
        header.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    putStr(0, 'RIFF');
    header.setUint32(4, _placeholderSize, Endian.little);
    putStr(8, 'WAVE');
    putStr(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little); // PCM
    header.setUint16(22, 1, Endian.little); // 单声道
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * 2, Endian.little);
    header.setUint16(32, 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    putStr(36, 'data');
    header.setUint32(40, _placeholderSize, Endian.little);
    return header.buffer.asUint8List();
  }
}
