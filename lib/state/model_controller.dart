import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../services/asr_engine.dart';
import '../services/diarization_engine.dart';
import '../services/model_manager.dart';

/// 模型发现与引擎加载状态管理（侧边栏「加载模型」面板）。
class ModelController extends ChangeNotifier {
  final ModelManager _manager = ModelManager();

  final AsrEngine asr = AsrEngine();
  final DiarizationEngine diarization = DiarizationEngine();

  ModelPaths? paths;
  bool scanning = false;
  bool loading = false;
  String? error;

  bool asrReady = false;
  bool diarReady = false;

  /// 模型文件是否齐备（ASR + VAD 为核心必需）。
  bool get coreReady => paths?.coreReady ?? false;

  /// 引擎是否可用（可以开始转写）。
  bool get ready => asrReady;

  bool get punctuationAvailable => paths?.punctuationReady ?? false;
  bool get diarizationAvailable => paths?.diarizationReady ?? false;

  String get dirDisplay => paths?.dir ?? '';

  /// 当前模型是否来自应用内置（随包打包，无需用户选择目录）。
  bool get usingBundled => paths?.bundled ?? false;

  /// 应用启动时：优先使用上次选择的目录，其次应用内置模型，
  /// 最后默认文档目录；找到核心模型即自动加载。
  Future<void> init() async {
    scanning = true;
    error = null;
    notifyListeners();

    final saved = await ModelManager.loadSavedDir();
    if (saved != null) {
      paths = await _manager.scan(saved);
      if (paths != null && !paths!.coreReady) {
        // 上次选择的目录内容不完整（被移动/删减）时继续尝试其他来源
        paths = null;
      }
    }
    paths ??= await _manager.scanBundled();
    paths ??= await _manager.scan((await ModelManager.defaultDir()).path);

    scanning = false;
    notifyListeners();

    if (coreReady) {
      await loadEngines();
    } else {
      error = '未找到模型文件：可先执行 make models 下载，'
          '或点击「选择」指定模型目录';
    }
  }

  /// 让用户选择模型目录并扫描。
  Future<void> chooseDirectory() async {
    final dir = await FilePicker.getDirectoryPath(dialogTitle: '选择模型目录');
    if (dir == null) return;

    scanning = true;
    error = null;
    notifyListeners();

    paths = await _manager.scan(dir);
    scanning = false;

    if (paths == null || !paths!.coreReady) {
      error = '该目录中未找到必需的模型文件（FireRedAsr2 / Silero VAD）';
    } else {
      await ModelManager.saveDir(dir);
    }
    notifyListeners();

    if (coreReady && !asrReady) await loadEngines();
  }

  /// 加载 ASR 引擎（FireRedAsr2 AED）。
  Future<void> loadEngines() async {
    if (loading || !coreReady || asrReady) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      await asr.load(paths: paths!);
      asrReady = true;
    } catch (e) {
      error = '模型加载失败：$e';
      asrReady = false;
    }
    loading = false;
    notifyListeners();
  }

  /// 确保说话人分离引擎就绪（可选能力）。
  Future<bool> ensureDiarization() async {
    if (diarReady) return true;
    if (!diarizationAvailable) return false;
    try {
      await diarization.load(paths: paths!);
      diarReady = true;
      notifyListeners();
      return true;
    } catch (e) {
      error = '说话人分离模型加载失败：$e';
      notifyListeners();
      return false;
    }
  }

  /// 释放全部引擎内存。
  Future<void> releaseEngines() async {
    await asr.quit();
    await diarization.quit();
    asrReady = false;
    diarReady = false;
    notifyListeners();
  }

  @override
  void dispose() {
    asr.quit();
    diarization.quit();
    super.dispose();
  }
}
