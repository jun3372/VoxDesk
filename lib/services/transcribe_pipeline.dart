import 'dart:async';
import 'dart:developer';
import 'dart:typed_data';

import '../data/transcript_models.dart';
import 'vad_engine.dart';

/// VAD 分段与 ASR 识别解耦的共享转写流水线（上传音频与实时录音
/// 重转写共用）。
///
/// VAD 按 512 窗口连续喂入、不被识别阻塞；每产出一个语音段立即派发
/// 识别（经 [recognize] 落到 ASR 池后可并发），在途数达到
/// [maxInFlight] 时暂停喂入做背压，避免长音频把所有语音段排队占内存。
/// 识别按段落派发的完成顺序乱序返回，[onSegment] 回调方负责按段落
/// 起点时间排序插入。
///
/// 取消（[isCancelled]）时停止喂入并丢弃未完成结果；暂停（[isPaused]）
/// 只暂停喂入，在途识别继续。
Future<void> streamTranscribe({
  required Float32List samples,
  required SegmentSource vad,
  required Future<String> Function(Float32List speechSamples) recognize,
  required bool Function() isCancelled,
  required bool Function() isPaused,
  required void Function(TranscriptSegment segment) onSegment,
  required void Function(double fedRatio) onProgress,
  required void Function() onChanged,
  int maxInFlight = 2,
}) async {
  // sherpa-onnx VAD 的状态机按「单窗口」粒度运行，段起点固定回看约
  // 0.7s；一次喂入多个窗口会把起点错定位到块尾，吞掉块内更早的语音，
  // 也无法在块内的静音处切段（官方注释 "n is usually window_size"）。
  // 必须按窗口粒度小步喂入。
  const windowSize = 512;
  const windowsPerYield = 32; // 约 1 秒让出一次事件循环
  final inFlightCap = maxInFlight < 1 ? 1 : maxInFlight;
  var fed = 0;
  var windows = 0;
  var inFlight = 0;
  final slotWaiters = <Completer<void>>[];
  final tasks = <Future<void>>[];

  void releaseSlot() {
    inFlight--;
    if (slotWaiters.isNotEmpty) slotWaiters.removeAt(0).complete();
  }

  // 取出当前所有已完成的语音段并派发识别（不等待结果）。
  Future<void> drainAndDispatch() async {
    while (vad.hasSegment) {
      final s = vad.front();
      vad.pop();
      if (isCancelled()) continue;
      final startSec = s.start / VadEngine.sampleRate;
      final endSec = (s.start + s.samples.length) / VadEngine.sampleRate;
      while (inFlight >= inFlightCap && !isCancelled()) {
        final c = Completer<void>();
        slotWaiters.add(c);
        await c.future;
      }
      if (isCancelled()) continue;
      inFlight++;
      tasks.add(
        () async {
          String text;
          try {
            text = await recognize(s.samples);
          } catch (e) {
            text = '';
            log('段落识别失败: $e', name: 'transcribe');
          }
          if (!isCancelled() && text.isNotEmpty) {
            onSegment(
              TranscriptSegment(
                startSec: startSec,
                endSec: endSec,
                text: text,
              ),
            );
          }
          onChanged();
        }().whenComplete(releaseSlot),
      );
    }
  }

  while (fed < samples.length && !isCancelled()) {
    while (isPaused() && !isCancelled()) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    if (isCancelled()) break;
    final end = (fed + windowSize).clamp(0, samples.length);
    vad.acceptWaveform(Float32List.sublistView(samples, fed, end));
    fed = end;
    await drainAndDispatch();
    onProgress(fed / samples.length);
    if (++windows % windowsPerYield == 0) {
      await Future<void>.delayed(Duration.zero);
    }
  }
  if (isCancelled()) return;
  vad.flush();
  await drainAndDispatch();
  // 等所有在途识别完成，保证返回时结果已齐全
  await Future.wait(tasks);
}
