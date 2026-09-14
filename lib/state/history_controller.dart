import 'package:flutter/foundation.dart';

import '../data/transcript_models.dart';
import '../services/history_service.dart';

/// 侧边栏历史记录列表状态。
class HistoryController extends ChangeNotifier {
  HistoryController(this._service);

  final HistoryService _service;
  List<HistoryItem> items = [];
  String? selectedId;

  /// 打开某条历史记录时对应的 Tab。
  int tabForItem(HistoryItem item) => item.type == HistoryType.file ? 0 : 1;

  Future<void> reload() async {
    items = await _service.loadAll();
    notifyListeners();
  }

  Future<List<TranscriptSegment>> loadSegments(HistoryItem item) =>
      _service.loadSegments(item);

  Future<String?> audioPathFor(HistoryItem item) async {
    if (item.type == HistoryType.file) return item.sourcePath;
    return _service.sessionAudioPath(item);
  }

  Future<void> remove(HistoryItem item) async {
    await _service.delete(item);
    if (selectedId == item.id) selectedId = null;
    await reload();
  }

  void select(String? id) {
    selectedId = id;
    notifyListeners();
  }

  HistoryItem? byId(String id) {
    for (final it in items) {
      if (it.id == id) return it;
    }
    return null;
  }
}
