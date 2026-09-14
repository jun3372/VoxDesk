/// 转写与历史记录的数据模型。
library;

/// 历史记录来源类型。
enum HistoryType { file, realtime }

extension HistoryTypeX on HistoryType {
  String get jsonName => this == HistoryType.file ? 'file' : 'realtime';

  String get displayName => this == HistoryType.file ? '上传音频' : '实时转写';

  static HistoryType fromJson(String v) =>
      v == 'realtime' ? HistoryType.realtime : HistoryType.file;
}

/// 一段带时间戳的转写结果。
class TranscriptSegment {
  TranscriptSegment({
    required this.startSec,
    required this.endSec,
    required this.text,
    this.speaker,
    this.speakerName,
  });

  final double startSec;
  final double endSec;
  String text;

  /// 说话人序号（从 0 开始）；null 表示未启用说话人分离。
  int? speaker;

  /// 用户自定义的说话人名称；null/空表示使用默认标签「说话人 N」。
  String? speakerName;

  Map<String, dynamic> toJson() => {
    'start': startSec,
    'end': endSec,
    'text': text,
    if (speaker != null) 'speaker': speaker,
    if (speakerName != null && speakerName!.isNotEmpty)
      'speakerName': speakerName,
  };

  factory TranscriptSegment.fromJson(Map<String, dynamic> json) {
    return TranscriptSegment(
      startSec: (json['start'] as num).toDouble(),
      endSec: (json['end'] as num?)?.toDouble() ?? 0,
      text: (json['text'] as String?) ?? '',
      speaker: json['speaker'] as int?,
      speakerName: json['speakerName'] as String?,
    );
  }

  /// 说话人展示名：自定义名称优先，否则 `说话人 1`。
  String get speakerLabel {
    if (speaker == null) return '';
    final name = speakerName;
    if (name != null && name.trim().isNotEmpty) return name.trim();
    return '说话人 ${(speaker! + 1)}';
  }

  /// 是否使用了自定义名称（用于界面区分与「恢复默认」）。
  bool get hasCustomSpeakerName =>
      speakerName != null && speakerName!.trim().isNotEmpty;
}

/// 历史记录条目（meta.json 对应的轻量元信息）。
class HistoryItem {
  HistoryItem({
    required this.id,
    required this.type,
    required this.title,
    required this.createdAt,
    required this.durationSec,
    required this.charCount,
    required this.segmentCount,
    this.sourcePath,
    this.device,
    this.fileSizeBytes,
  });

  final String id;
  final HistoryType type;
  final String title;
  final DateTime createdAt;
  final double durationSec;
  final int charCount;
  final int segmentCount;

  /// 文件转写：原始音频路径（回放用）。
  final String? sourcePath;

  /// 实时会话：录音设备描述。
  final String? device;

  final int? fileSizeBytes;

  HistoryItem copyWith({int? charCount, int? segmentCount}) => HistoryItem(
    id: id,
    type: type,
    title: title,
    createdAt: createdAt,
    durationSec: durationSec,
    charCount: charCount ?? this.charCount,
    segmentCount: segmentCount ?? this.segmentCount,
    sourcePath: sourcePath,
    device: device,
    fileSizeBytes: fileSizeBytes,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.jsonName,
    'title': title,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'durationSec': durationSec,
    'charCount': charCount,
    'segmentCount': segmentCount,
    if (sourcePath != null) 'sourcePath': sourcePath,
    if (device != null) 'device': device,
    if (fileSizeBytes != null) 'fileSizeBytes': fileSizeBytes,
  };

  factory HistoryItem.fromJson(Map<String, dynamic> json) => HistoryItem(
    id: json['id'] as String,
    type: HistoryTypeX.fromJson(json['type'] as String? ?? 'file'),
    title: json['title'] as String? ?? '未命名',
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (json['createdAt'] as num).toInt(),
    ),
    durationSec: (json['durationSec'] as num?)?.toDouble() ?? 0,
    charCount: (json['charCount'] as num?)?.toInt() ?? 0,
    segmentCount: (json['segmentCount'] as num?)?.toInt() ?? 0,
    sourcePath: json['sourcePath'] as String?,
    device: json['device'] as String?,
    fileSizeBytes: json['fileSizeBytes'] as int?,
  );
}

/// 将 VAD 语音段与说话人分离结果按时间重叠匹配，回填说话人标签。
/// 返回新列表，不修改输入。
List<TranscriptSegment> assignSpeakers({
  required List<TranscriptSegment> segments,
  required List<({double start, double end, int speaker})> diarSegments,
}) {
  if (diarSegments.isEmpty) return segments;

  final result = <TranscriptSegment>[];
  for (final seg in segments) {
    int? bestSpeaker;
    var bestOverlap = 0.0;
    for (final d in diarSegments) {
      final overlap =
          (seg.endSec < d.end ? seg.endSec : d.end) -
          (seg.startSec > d.start ? seg.startSec : d.start);
      if (overlap > bestOverlap) {
        bestOverlap = overlap;
        bestSpeaker = d.speaker;
      }
    }
    result.add(
      TranscriptSegment(
        startSec: seg.startSec,
        endSec: seg.endSec,
        text: seg.text,
        speaker: bestSpeaker,
        // 分离结果可能多次回填（增量分离 → 结束时全量分离），
        // 保留用户已设置的自定义说话人名
        speakerName: seg.speakerName,
      ),
    );
  }
  return result;
}
