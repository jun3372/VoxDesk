/// 最小 WAV 读写工具：解析 RIFF/WAVE（PCM16 / PCM Float32），
/// 以及写出 16kHz 单声道 PCM16 WAV。
library;

import 'dart:io';
import 'dart:math';
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
      // 视图而非拷贝：长音频的 data 块动辄上百 MB
      data = Uint8List.sublistView(bytes, body, end);
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
        samples = Float32List(n);
        // 小端主机且偏移对齐时直接用 Int16List 视图批量转换，
        // 比逐样本 ByteData.getInt16 快一个数量级
        if (Endian.host == Endian.little && data.offsetInBytes % 2 == 0) {
          final ints = Int16List.view(data.buffer, data.offsetInBytes, n);
          for (var i = 0; i < n; i++) {
            samples[i] = ints[i] / 32768.0;
          }
        } else {
          final dv = ByteData.sublistView(data);
          for (var i = 0; i < n; i++) {
            samples[i] = dv.getInt16(i * 2, Endian.little) / 32768.0;
          }
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
      // 视图要求 4 字节对齐：data 块起始偏移非对齐时（前置奇长元数据块）
      // 退回逐样本读取，与 PCM16 分支的对齐保护一致
      if (Endian.host == Endian.little && data.offsetInBytes % 4 == 0) {
        samples = Float32List.view(
          data.buffer,
          data.offsetInBytes,
          n,
        ).sublist(0, n);
      } else {
        final dv = ByteData.sublistView(data);
        samples = Float32List(n);
        for (var i = 0; i < n; i++) {
          samples[i] = dv.getFloat32(i * 4, Endian.little);
        }
      }
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

/// 流式读取 WAV 文件为 [WavData]：按块读取 data 块直接填充
/// Float32List，不产生全量字节拷贝，适合大录音文件。
///
/// 仅支持 PCM16 与 IEEE Float32；其他编码回退到整读 [parseWav]。
/// data 块声明尺寸大于文件实际剩余时按实际剩余读取（兼容
/// 录制中尚未回填头部尺寸的半成品文件）。
Future<WavData> readWavStreamed(String path) async {
  final file = File(path);
  final raf = await file.open();
  try {
    final fileLen = await raf.length();
    final riff = await raf.read(12);
    if (riff.length < 12 ||
        riff[0] != 0x52 ||
        riff[1] != 0x49 ||
        riff[2] != 0x46 ||
        riff[3] != 0x46) {
      throw const FormatException('不是有效的 WAV 文件（缺少 RIFF 头）');
    }

    int? sampleRate;
    int? channels;
    int bits = 16;
    var formatTag = 1;
    int? dataOffset;
    var dataSize = 0;

    while (true) {
      final head = await raf.read(8);
      if (head.length < 8) break;
      final id = String.fromCharCodes(head.sublist(0, 4));
      final size = ByteData.sublistView(head).getUint32(4, Endian.little);
      final bodyPos = await raf.position();
      if (id == 'fmt ') {
        final fmt = await raf.read(min(size, 64));
        if (fmt.length < 16) break;
        final fv = ByteData.sublistView(fmt);
        formatTag = fv.getUint16(0, Endian.little);
        channels = fv.getUint16(2, Endian.little);
        sampleRate = fv.getUint32(4, Endian.little);
        bits = fv.getUint16(14, Endian.little);
      } else if (id == 'data') {
        dataOffset = bodyPos;
        dataSize = size;
        break;
      }
      await raf.setPosition(bodyPos + size + (size.isOdd ? 1 : 0));
    }

    if (dataOffset == null || sampleRate == null || channels == null) {
      throw const FormatException('WAV 缺少 fmt/data 块');
    }
    final supported =
        (formatTag == 1 && bits == 16) || (formatTag == 3 && bits == 32);
    if (!supported) {
      // 不支持的编码：回退整读解析
      await raf.close();
      return parseWav(await file.readAsBytes());
    }

    // 头部尺寸可能是占位大值（录制中），按文件实际剩余兜底
    final bytesPerSample = bits ~/ 8;
    final available = (fileLen - dataOffset) ~/ bytesPerSample;
    final declared = dataSize ~/ bytesPerSample;
    final total = min(declared, available);
    final out = Float32List(total);

    var filled = 0;
    const chunkSamples = 32768; // 每块 64KB/128KB
    while (filled < total) {
      final want = min(chunkSamples, total - filled);
      final bytes = await raf.read(want * bytesPerSample);
      if (bytes.isEmpty) break;
      final n = bytes.length ~/ bytesPerSample;
      final aligned = Endian.host == Endian.little &&
          bytes.offsetInBytes % bytesPerSample == 0;
      if (formatTag == 1) {
        if (aligned) {
          // 类型化视图批量转换，避免逐样本 ByteData.getInt16
          final ints = Int16List.view(bytes.buffer, bytes.offsetInBytes, n);
          for (var i = 0; i < n; i++) {
            out[filled + i] = ints[i] / 32768.0;
          }
        } else {
          final bd = ByteData.sublistView(bytes);
          for (var i = 0; i < n; i++) {
            out[filled + i] = bd.getInt16(i * 2, Endian.little) / 32768.0;
          }
        }
      } else {
        if (aligned) {
          out.setRange(
            filled,
            filled + n,
            Float32List.view(bytes.buffer, bytes.offsetInBytes, n),
          );
        } else {
          final bd = ByteData.sublistView(bytes);
          for (var i = 0; i < n; i++) {
            out[filled + i] = bd.getFloat32(i * 4, Endian.little);
          }
        }
      }
      filled += n;
    }
    if (filled < total) return WavData(out.sublist(0, filled), sampleRate, channels);
    return WavData(out, sampleRate, channels);
  } finally {
    try {
      await raf.close();
    } catch (_) {}
  }
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
