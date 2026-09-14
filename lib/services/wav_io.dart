/// 最小 WAV 读写工具：解析 RIFF/WAVE（PCM16 / PCM Float32），
/// 以及写出 16kHz 单声道 PCM16 WAV。
library;

import 'dart:typed_data';

class WavData {
  const WavData(this.samples, this.sampleRate, this.channels);

  /// 交错采样，归一化到 -1.0..1.0。
  final Float32List samples;
  final int sampleRate;
  final int channels;
}

/// 解析 WAV 字节。支持 PCM 8/16/24/32 与 IEEE float 32/64。
/// 解析失败抛 [FormatException]。
WavData parseWav(Uint8List bytes) {
  if (bytes.length < 44 ||
      bytes[0] != 0x52 ||
      bytes[1] != 0x49 ||
      bytes[2] != 0x46 ||
      bytes[3] != 0x46) {
    throw const FormatException('不是有效的 WAV 文件（缺少 RIFF 头）');
  }

  final view = ByteData.sublistView(bytes);
  var offset = 12; // 跳过 "RIFF" + size + "WAVE"
  int? sampleRate;
  int? channels;
  int? bitsPerSample;
  int formatTag = 1;
  Uint8List? data;

  while (offset + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final size = view.getUint32(offset + 4, Endian.little);
    final body = offset + 8;
    if (id == 'fmt ') {
      formatTag = view.getUint16(body, Endian.little);
      channels = view.getUint16(body + 2, Endian.little);
      sampleRate = view.getUint32(body + 4, Endian.little);
      bitsPerSample = view.getUint16(body + 14, Endian.little);
    } else if (id == 'data') {
      final end = (body + size).clamp(0, bytes.length);
      data = bytes.sublist(body, end);
    }
    offset = body + size + (size.isOdd ? 1 : 0);
    if (size <= 0) break;
  }

  if (data == null || sampleRate == null || channels == null) {
    throw const FormatException('WAV 缺少 fmt/data 块');
  }
  final bits = bitsPerSample ?? 16;

  Float32List samples;
  if (formatTag == 1) {
    switch (bits) {
      case 8:
        samples = Float32List(data.length);
        for (var i = 0; i < data.length; i++) {
          samples[i] = (data[i] - 128) / 128.0;
        }
      case 16:
        final n = data.length ~/ 2;
        final dv = ByteData.sublistView(data);
        samples = Float32List(n);
        for (var i = 0; i < n; i++) {
          samples[i] = dv.getInt16(i * 2, Endian.little) / 32768.0;
        }
      case 24:
        final n = data.length ~/ 3;
        samples = Float32List(n);
        for (var i = 0; i < n; i++) {
          var v = data[i * 3] | (data[i * 3 + 1] << 8) | (data[i * 3 + 2] << 16);
          if (v & 0x800000 != 0) v -= 0x1000000; // 符号扩展
          samples[i] = v / 8388608.0;
        }
      case 32:
        final n = data.length ~/ 4;
        final dv = ByteData.sublistView(data);
        samples = Float32List(n);
        for (var i = 0; i < n; i++) {
          samples[i] = dv.getInt32(i * 4, Endian.little) / 2147483648.0;
        }
      default:
        throw FormatException('不支持的 PCM 位深: $bits');
    }
  } else if (formatTag == 3) {
    if (bits == 32) {
      final n = data.length ~/ 4;
      samples = Float32List.view(
        data.buffer,
        data.offsetInBytes,
        n,
      ).sublist(0, n);
    } else if (bits == 64) {
      final n = data.length ~/ 8;
      final dv = ByteData.sublistView(data);
      samples = Float32List(n);
      for (var i = 0; i < n; i++) {
        samples[i] = dv.getFloat64(i * 8, Endian.little);
      }
    } else {
      throw FormatException('不支持的 float 位深: $bits');
    }
  } else {
    throw FormatException('不支持的 WAV 编码: formatTag=$formatTag');
  }

  return WavData(samples, sampleRate, channels);
}

/// 写出 16-bit PCM WAV 字节。
Uint8List writeWav(Float32List samples, int sampleRate, int channels) {
  const bitsPerSample = 16;
  final dataSize = samples.length * 2;
  final out = BytesBuilder();
  final header = ByteData(44);

  void putStr(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      header.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  putStr(0, 'RIFF');
  header.setUint32(4, 36 + dataSize, Endian.little);
  putStr(8, 'WAVE');
  putStr(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little); // PCM
  header.setUint16(22, channels, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, sampleRate * channels * bitsPerSample ~/ 8, Endian.little);
  header.setUint16(32, channels * bitsPerSample ~/ 8, Endian.little);
  header.setUint16(34, bitsPerSample, Endian.little);
  putStr(36, 'data');
  header.setUint32(40, dataSize, Endian.little);
  out.add(header.buffer.asUint8List());

  final pcm = ByteData(dataSize);
  for (var i = 0; i < samples.length; i++) {
    var v = samples[i].clamp(-1.0, 1.0);
    pcm.setInt16(i * 2, (v * 32767).round(), Endian.little);
  }
  out.add(pcm.buffer.asUint8List());
  return out.toBytes();
}

/// 任意采样率/声道数 → 16kHz 单声道（线性插值 + 均值混音）。
Float32List toMono16k(Float32List interleaved, int sampleRate, int channels) {
  // 混音为单声道
  final Float32List mono;
  if (channels <= 1) {
    mono = interleaved;
  } else {
    final frames = interleaved.length ~/ channels;
    mono = Float32List(frames);
    for (var f = 0; f < frames; f++) {
      var sum = 0.0;
      for (var c = 0; c < channels; c++) {
        sum += interleaved[f * channels + c];
      }
      mono[f] = sum / channels;
    }
  }

  if (sampleRate == 16000) return mono;

  final ratio = sampleRate / 16000;
  final outLen = (mono.length / ratio).floor();
  final out = Float32List(outLen);
  for (var i = 0; i < outLen; i++) {
    final src = i * ratio;
    final i0 = src.floor();
    final i1 = (i0 + 1).clamp(0, mono.length - 1);
    final frac = src - i0;
    out[i] = mono[i0] * (1 - frac) + mono[i1.clamp(0, mono.length - 1)] * frac;
  }
  return out;
}
