import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:voxdesk/data/transcript_models.dart';
import 'package:voxdesk/services/docx_exporter.dart';

void main() {
  test('DOCX 导出生成合法文件', () {
    final bytes = DocxExporter.build(
      title: '会议录音转写 & <特殊> "字符" 测试',
      segments: [
        TranscriptSegment(
            startSec: 0,
            endSec: 3.2,
            text: '大家好，今天我们聊一下《语音识别》的最新进展。',
            speaker: 0),
        TranscriptSegment(
            startSec: 4,
            endSec: 8,
            text: '好的，没问题——包含 "引号" 与 <尖括号> 与 & 符号的转义测试。',
            speaker: 1,
            speakerName: '张三'),
      ],
      createdAt: DateTime(2026, 9, 13, 10, 30),
      durationSec: 128.4,
    );
    expect(bytes.length, greaterThan(0));
    File('/tmp/voxdesk_test_export.docx').writeAsBytesSync(bytes);
  });
}
