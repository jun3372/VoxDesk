import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../core/formatters.dart';
import '../data/transcript_models.dart';
import 'app_data.dart';
import 'wav_io.dart';

/// 实时会话草稿：录音文件已落盘但尚未写入元信息，
/// 不会出现在历史列表；待说话人标注完成后调用
/// [HistoryService.finalizeRealtimeSession] 转正为唯一一份历史记录。
class RealtimeSessionDraft {
  const RealtimeSessionDraft({
    required this.id,
    required this.createdAt,
    required this.durationSec,
    required this.device,
    this.audioPath,
  });

  final String id;
  final DateTime createdAt;
  final double durationSec;
  final String device;

  /// 已落盘的录音文件路径；null 表示写盘失败。
  final String? audioPath;
}

/// 历史记录持久化服务。
///
/// 目录结构：`<文档目录>/VoxDesk/history/<id>/`
/// - `meta.json`       条目元信息
/// - `transcript.json` 转写段列表
/// - `session.wav`     实时会话录音（仅实时转写）
class HistoryService {
  HistoryService(this.root);

  final Directory root;

  static Future<HistoryService> create() async {
    final dataDir = await appDataDir();
    final dir = Directory('${dataDir.path}${Platform.pathSeparator}history');
    if (!dir.existsSync()) await dir.create(recursive: true);
    final service = HistoryService(dir);
    // 启动时清理说话人标注未完成就退出的残留草稿（此时不可能有运行中的会话）
    await service.cleanDrafts();
    return service;
  }

  Directory _itemDir(String id) =>
      Directory('${root.path}${Platform.pathSeparator}$id');

  Future<List<HistoryItem>> loadAll() async {
    final items = <HistoryItem>[];
    if (!root.existsSync()) return items;
    await for (final e in root.list()) {
      if (e is! Directory) continue;
      final meta = File('${e.path}${Platform.pathSeparator}meta.json');
      if (!meta.existsSync()) continue;
      try {
        items.add(
          HistoryItem.fromJson(
            jsonDecode(await meta.readAsString()) as Map<String, dynamic>,
          ),
        );
      } catch (_) {
        // 忽略损坏的历史条目
      }
    }
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  Future<HistoryItem> saveFileResult({
    required String title,
    required String sourcePath,
    required double durationSec,
    required List<TranscriptSegment> segments,
    int? fileSizeBytes,
  }) async {
    return _save(
      HistoryType.file,
      title: title,
      durationSec: durationSec,
      segments: segments,
      sourcePath: sourcePath,
      fileSizeBytes: fileSizeBytes,
    );
  }

  /// 实时会话两段式保存的第一步：仅落盘录音文件，供结束页立即回放；
  /// 此时不写 meta/transcript，历史列表不会出现该条目。
  Future<RealtimeSessionDraft> createRealtimeSessionDraft({
    required DateTime createdAt,
    required double durationSec,
    required String device,
    Float32List? audio,
  }) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final dir = _itemDir(id);
    await dir.create(recursive: true);

    String? audioPath;
    if (audio != null && audio.isNotEmpty) {
      try {
        audioPath = '${dir.path}${Platform.pathSeparator}session.wav';
        await File(audioPath).writeAsBytes(writeWav(audio, 16000, 1));
      } catch (_) {
        audioPath = null; // 录音保存失败不影响文字记录
      }
    }
    return RealtimeSessionDraft(
      id: id,
      createdAt: createdAt,
      durationSec: durationSec,
      device: device,
      audioPath: audioPath,
    );
  }

  /// 第二步：写入元信息与转写结果（含说话人标注后的最终文本），
  /// 条目自此作为唯一一份记录出现在历史列表。
  Future<HistoryItem> finalizeRealtimeSession(
    RealtimeSessionDraft draft,
    List<TranscriptSegment> segments,
  ) async {
    final charCount = segments.fold<int>(
      0,
      (n, s) => n + s.text.replaceAll(' ', '').length,
    );
    final item = HistoryItem(
      id: draft.id,
      type: HistoryType.realtime,
      title: '实时转写会话',
      createdAt: draft.createdAt,
      durationSec: draft.durationSec,
      charCount: charCount,
      segmentCount: segments.length,
      device: draft.device,
    );

    final dir = _itemDir(draft.id);
    await File('${dir.path}${Platform.pathSeparator}meta.json')
        .writeAsString(jsonEncode(item.toJson()));
    await File('${dir.path}${Platform.pathSeparator}transcript.json')
        .writeAsString(jsonEncode([for (final s in segments) s.toJson()]));
    return item;
  }

  /// 清理残留草稿（只有录音、没有 meta.json 的目录）。
  /// 仅应在应用启动时调用，运行中的草稿不会被误删。
  Future<void> cleanDrafts() async {
    if (!root.existsSync()) return;
    await for (final e in root.list()) {
      if (e is! Directory) continue;
      final meta = File('${e.path}${Platform.pathSeparator}meta.json');
      if (meta.existsSync()) continue;
      try {
        await e.delete(recursive: true);
      } catch (_) {
        // 清理失败不影响主流程
      }
    }
  }

  Future<HistoryItem> _save(
    HistoryType type, {
    required String title,
    required double durationSec,
    required List<TranscriptSegment> segments,
    String? sourcePath,
    String? device,
    int? fileSizeBytes,
    DateTime? createdAt,
  }) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final dir = _itemDir(id);
    await dir.create(recursive: true);

    final charCount = segments.fold<int>(
      0,
      (n, s) => n + s.text.replaceAll(' ', '').length,
    );
    final item = HistoryItem(
      id: id,
      type: type,
      title: title,
      createdAt: createdAt ?? DateTime.now(),
      durationSec: durationSec,
      charCount: charCount,
      segmentCount: segments.length,
      sourcePath: sourcePath,
      device: device,
      fileSizeBytes: fileSizeBytes,
    );

    await File('${dir.path}${Platform.pathSeparator}meta.json')
        .writeAsString(jsonEncode(item.toJson()));
    await File('${dir.path}${Platform.pathSeparator}transcript.json')
        .writeAsString(jsonEncode([for (final s in segments) s.toJson()]));
    return item;
  }

  Future<List<TranscriptSegment>> loadSegments(HistoryItem item) async {
    final f = File(
      '${_itemDir(item.id).path}${Platform.pathSeparator}transcript.json',
    );
    if (!f.existsSync()) return [];
    try {
      final list = jsonDecode(await f.readAsString()) as List;
      return [
        for (final e in list)
          TranscriptSegment.fromJson(e as Map<String, dynamic>),
      ];
    } catch (_) {
      return [];
    }
  }

  /// 覆盖更新已有条目的转写结果（重新转写场景，不新增记录）。
  /// 条目不存在或元信息损坏时返回 false。
  Future<bool> updateSegments(
    String id,
    List<TranscriptSegment> segments,
  ) async {
    final metaFile = File(
      '${_itemDir(id).path}${Platform.pathSeparator}meta.json',
    );
    if (!metaFile.existsSync()) return false;
    HistoryItem item;
    try {
      item = HistoryItem.fromJson(
        jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>,
      );
    } catch (_) {
      return false;
    }
    final charCount = segments.fold<int>(
      0,
      (n, s) => n + s.text.replaceAll(' ', '').length,
    );
    await metaFile.writeAsString(
      jsonEncode(
        item
            .copyWith(charCount: charCount, segmentCount: segments.length)
            .toJson(),
      ),
    );
    await File('${_itemDir(id).path}${Platform.pathSeparator}transcript.json')
        .writeAsString(jsonEncode([for (final s in segments) s.toJson()]));
    return true;
  }

  /// 实时会话录音路径（无则返回 null）。
  Future<String?> sessionAudioPath(HistoryItem item) async {
    final f = File(
      '${_itemDir(item.id).path}${Platform.pathSeparator}session.wav',
    );
    return f.existsSync() ? f.path : null;
  }

  Future<void> delete(HistoryItem item) async {
    final dir = _itemDir(item.id);
    if (dir.existsSync()) await dir.delete(recursive: true);
  }

  /// 生成导出文本：`[00:00:00] 说话人 1: 内容`。
  static String buildExportText(
    List<TranscriptSegment> segments, {
    bool withSpeakers = true,
  }) {
    final buf = StringBuffer();
    for (final s in segments) {
      buf.write('[${formatClock(s.startSec)}]');
      if (withSpeakers && s.speaker != null) buf.write(' ${s.speakerLabel}:');
      buf.write(' ${s.text}');
      buf.writeln();
    }
    return buf.toString();
  }
}
