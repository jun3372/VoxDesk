import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:voxdesk/data/transcript_models.dart';
import 'package:voxdesk/services/history_service.dart';

void main() {
  late Directory tempDir;
  late HistoryService service;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('voxdesk_history_test');
    service = HistoryService(tempDir);
  });

  tearDown(() {
    tempDir.delete(recursive: true);
  });

  TranscriptSegment seg(String text, {int? speaker}) =>
      TranscriptSegment(startSec: 0, endSec: 1, text: text, speaker: speaker);

  Future<RealtimeSessionDraft> newDraft() =>
      service.createRealtimeSessionDraft(
        createdAt: DateTime(2026, 9, 13, 10, 0),
        durationSec: 12,
        device: '测试麦克风',
        audio: Float32List.fromList([0.5, -0.5, 0.25]),
      );

  test('草稿在 finalize 前不出现在历史列表，但录音文件已落盘可回放', () async {
    final draft = await newDraft();

    expect(await service.loadAll(), isEmpty);
    expect(draft.audioPath, isNotNull);
    expect(File(draft.audioPath!).existsSync(), isTrue);

    final item = HistoryItem(
      id: draft.id,
      type: HistoryType.realtime,
      title: '实时转写会话',
      createdAt: draft.createdAt,
      durationSec: draft.durationSec,
      charCount: 0,
      segmentCount: 0,
    );
    expect(await service.sessionAudioPath(item), draft.audioPath);
  });

  test('finalize 后只生成一份带说话人的历史记录', () async {
    final draft = await newDraft();
    final item = await service.finalizeRealtimeSession(draft, [
      seg('你好', speaker: 0),
      seg('再见', speaker: 1),
    ]);

    final items = await service.loadAll();
    expect(items, hasLength(1));
    expect(items.first.id, draft.id);
    expect(items.first.type, HistoryType.realtime);
    expect(items.first.charCount, 4);
    expect(items.first.segmentCount, 2);
    expect(item.id, draft.id);

    final segs = await service.loadSegments(items.first);
    expect(segs, hasLength(2));
    expect(segs[0].speakerLabel, '说话人 1');
    expect(segs[1].speakerLabel, '说话人 2');
  });

  test('cleanDrafts 只清理草稿，不影响已 finalize 的记录', () async {
    final draft = await newDraft();
    await service.finalizeRealtimeSession(draft, [seg('保留')]);
    // 另造一个未 finalize 的草稿目录
    await service.createRealtimeSessionDraft(
      createdAt: DateTime(2026, 9, 13, 11, 0),
      durationSec: 3,
      device: '测试麦克风',
    );

    await service.cleanDrafts();

    final items = await service.loadAll();
    expect(items, hasLength(1));
    expect((await service.loadSegments(items.first)).single.text, '保留');
  });

  test('finalize 后仍可通过 updateSegments 更新（重新转写场景）', () async {
    final draft = await newDraft();
    await service.finalizeRealtimeSession(draft, [seg('原始文本')]);

    final ok = await service.updateSegments(draft.id, [seg('更新后的文本')]);
    expect(ok, isTrue);

    final items = await service.loadAll();
    expect(items, hasLength(1));
    expect((await service.loadSegments(items.first)).single.text, '更新后的文本');
  });

  test('结束即 finalize 立即可见，后台标注原地更新且不新增条目', () async {
    final draft = await newDraft();

    // 录音结束：先写入未标注的记录，历史列表立即可见
    await service.finalizeRealtimeSession(draft, [seg('你好')]);
    final visible = await service.loadAll();
    expect(visible, hasLength(1));
    expect((await service.loadSegments(visible.first)).single.speaker, isNull);

    // 后台说话人标注完成：原地更新为带标签版本
    final ok = await service.updateSegments(draft.id, [seg('你好', speaker: 0)]);
    expect(ok, isTrue);

    final items = await service.loadAll();
    expect(items, hasLength(1));
    expect(items.first.id, draft.id);
    expect((await service.loadSegments(items.first)).single.speakerLabel, '说话人 1');
  });
}
