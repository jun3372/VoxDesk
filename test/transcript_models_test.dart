import 'package:flutter_test/flutter_test.dart';

import 'package:voxdesk/data/transcript_models.dart';

void main() {
  group('assignSpeakers', () {
    test('按最大时间重叠回填说话人', () {
      final segments = [
        TranscriptSegment(startSec: 0, endSec: 4, text: 'a'),
        TranscriptSegment(startSec: 5, endSec: 9, text: 'b'),
      ];
      final result = assignSpeakers(
        segments: segments,
        diarSegments: [
          (start: 0.0, end: 5.0, speaker: 0),
          (start: 5.0, end: 10.0, speaker: 1),
        ],
      );
      expect(result[0].speaker, 0);
      expect(result[1].speaker, 1);
    });

    test('空分离结果时保持原样（speaker 为 null）', () {
      final segments = [
        TranscriptSegment(startSec: 0, endSec: 4, text: 'a'),
      ];
      final result = assignSpeakers(segments: segments, diarSegments: []);
      expect(result.length, 1);
      expect(result[0].speaker, isNull);
    });

    test('不修改输入列表对象', () {
      final seg = TranscriptSegment(startSec: 0, endSec: 4, text: 'a');
      assignSpeakers(
        segments: [seg],
        diarSegments: [(start: 0.0, end: 5.0, speaker: 2)],
      );
      expect(seg.speaker, isNull);
    });
  });

  group('TranscriptSegment JSON', () {
    test('序列化与反序列化（含说话人）', () {
      final seg = TranscriptSegment(
        startSec: 1.5,
        endSec: 3.2,
        text: '你好世界',
        speaker: 1,
      );
      final restored = TranscriptSegment.fromJson(seg.toJson());
      expect(restored.startSec, 1.5);
      expect(restored.endSec, 3.2);
      expect(restored.text, '你好世界');
      expect(restored.speaker, 1);
      expect(restored.speakerLabel, '说话人 2');
    });

    test('无说话人时 JSON 不含 speaker 字段', () {
      final seg = TranscriptSegment(startSec: 0, endSec: 1, text: 'x');
      expect(seg.toJson().containsKey('speaker'), isFalse);
    });
  });

  group('HistoryItem JSON', () {
    test('序列化与反序列化', () {
      final item = HistoryItem(
        id: '42',
        type: HistoryType.realtime,
        title: '实时转写会话',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        durationSec: 516,
        charCount: 100,
        segmentCount: 8,
        device: '系统默认麦克风',
      );
      final restored = HistoryItem.fromJson(item.toJson());
      expect(restored.id, '42');
      expect(restored.type, HistoryType.realtime);
      expect(restored.durationSec, 516);
      expect(restored.device, '系统默认麦克风');
      expect(restored.sourcePath, isNull);
    });
  });
}
