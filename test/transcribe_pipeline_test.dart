import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:voxdesk/data/transcript_models.dart';
import 'package:voxdesk/services/transcribe_pipeline.dart';
import 'package:voxdesk/services/vad_engine.dart';

/// 假 VAD：每喂入 [segmentEveryWindows] 个窗口产出一个语音段。
class FakeVad implements SegmentSource {
  FakeVad({this.segmentEveryWindows = 10, this.segmentSamples = 512});

  final int segmentEveryWindows;
  final int segmentSamples;
  final _pending = <({Float32List samples, int start})>[];
  var _fed = 0;

  @override
  void acceptWaveform(Float32List window) {
    _fed++;
    if (_fed % segmentEveryWindows == 0) {
      _pending.add((
        samples: Float32List(segmentSamples),
        start: _fed * 512,
      ));
    }
  }

  @override
  bool get hasSegment => _pending.isNotEmpty;

  @override
  ({Float32List samples, int start}) front() => _pending.first;

  @override
  void pop() => _pending.removeAt(0);

  @override
  void flush() {}
}

void main() {
  group('streamTranscribe', () {
    test('乱序完成的识别结果按段落起点排序回显', () async {
      // 40 个窗口 → 4 个语音段；让越早的段识别越慢，强制乱序完成
      final vad = FakeVad();
      final samples = Float32List(512 * 40);
      final result = <TranscriptSegment>[];
      final rng = Random(1);

      await streamTranscribe(
        samples: samples,
        vad: vad,
        maxInFlight: 4,
        recognize: (speech) async {
          await Future<void>.delayed(
            Duration(milliseconds: rng.nextInt(40)),
          );
          return '文本';
        },
        isCancelled: () => false,
        isPaused: () => false,
        onSegment: (seg) {
          var i = result.length;
          while (i > 0 && result[i - 1].startSec > seg.startSec) {
            i--;
          }
          result.insert(i, seg);
        },
        onProgress: (_) {},
        onChanged: () {},
      );

      expect(result.length, 4);
      for (var i = 1; i < result.length; i++) {
        expect(result[i].startSec > result[i - 1].startSec, isTrue);
      }
    });

    test('并发派发：识别不阻塞后续段落提交', () async {
      final vad = FakeVad();
      final samples = Float32List(512 * 30); // 3 段
      var concurrent = 0;
      var maxConcurrent = 0;

      await streamTranscribe(
        samples: samples,
        vad: vad,
        maxInFlight: 4,
        recognize: (speech) async {
          concurrent++;
          maxConcurrent = max(maxConcurrent, concurrent);
          await Future<void>.delayed(const Duration(milliseconds: 30));
          concurrent--;
          return '文本';
        },
        isCancelled: () => false,
        isPaused: () => false,
        onSegment: (_) {},
        onProgress: (_) {},
        onChanged: () {},
      );

      expect(maxConcurrent, greaterThan(1));
    });

    test('背压：在途数不超过 maxInFlight', () async {
      final vad = FakeVad();
      final samples = Float32List(512 * 50); // 5 段
      var inFlight = 0;
      var maxSeen = 0;

      await streamTranscribe(
        samples: samples,
        vad: vad,
        maxInFlight: 2,
        recognize: (speech) async {
          inFlight++;
          maxSeen = max(maxSeen, inFlight);
          await Future<void>.delayed(const Duration(milliseconds: 10));
          inFlight--;
          return '文本';
        },
        isCancelled: () => false,
        isPaused: () => false,
        onSegment: (_) {},
        onProgress: (_) {},
        onChanged: () {},
      );

      expect(maxSeen, lessThanOrEqualTo(2));
    });

    test('取消：停止喂入且丢弃未完成结果', () async {
      final vad = FakeVad();
      final samples = Float32List(512 * 40); // 4 段
      var cancelled = false;
      var recognizeCalls = 0;
      final result = <TranscriptSegment>[];

      await streamTranscribe(
        samples: samples,
        vad: vad,
        maxInFlight: 4,
        recognize: (speech) async {
          recognizeCalls++;
          if (recognizeCalls == 1) cancelled = true; // 首段识别中取消
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return '文本';
        },
        isCancelled: () => cancelled,
        isPaused: () => false,
        onSegment: result.add,
        onProgress: (_) {},
        onChanged: () {},
      );

      expect(result, isEmpty);
      expect(recognizeCalls, lessThan(4));
    });

    test('空文本段落被丢弃', () async {
      final vad = FakeVad();
      final samples = Float32List(512 * 20); // 2 段
      final result = <TranscriptSegment>[];
      var calls = 0;

      await streamTranscribe(
        samples: samples,
        vad: vad,
        recognize: (speech) async => ++calls == 1 ? '' : '有内容',
        isCancelled: () => false,
        isPaused: () => false,
        onSegment: result.add,
        onProgress: (_) {},
        onChanged: () {},
      );

      expect(result.length, 1);
      expect(result.single.text, '有内容');
    });

    test('段落识别异常通过 onSegmentError 上浮且不中断后续段落', () async {
      final vad = FakeVad();
      final samples = Float32List(512 * 20); // 2 段
      final result = <TranscriptSegment>[];
      final errors = <Object>[];
      var calls = 0;

      await streamTranscribe(
        samples: samples,
        vad: vad,
        recognize: (speech) async {
          calls++;
          if (calls == 1) throw StateError('引擎故障');
          return '有内容';
        },
        isCancelled: () => false,
        isPaused: () => false,
        onSegment: result.add,
        onProgress: (_) {},
        onChanged: () {},
        onSegmentError: errors.add,
      );

      expect(result.length, 1);
      expect(result.single.text, '有内容');
      expect(errors.length, 1);
      expect(errors.single, isA<StateError>());
    });
  });
}
