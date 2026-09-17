import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MissingPluginException;

import '../services/asr_engine.dart';
import '../services/device_tuning.dart';
import '../services/diarization_engine.dart';
import '../services/model_manager.dart';

/// 模型发现与引擎加载状态管理（侧边栏「加载模型」面板）。
class ModelController extends ChangeNotifier {
  final ModelManager _manager = ModelManager();

  final AsrEnginePool asr = AsrEnginePool();
  final DiarizationEngine diarization = DiarizationEngine();

  /// 设备算力探测结果（worker 数/线程数），首次加载引擎时计算并缓存。
  DeviceTuning? _tuning;
  Future<DeviceTuning> _deviceTuning() async =>
      _tuning ??= await probeDeviceTuning();

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
  ///
  /// 各平台的目录选择对话框实现参差：macOS 的纯目录对话框
  /// （NSOpenPanel canChooseFiles=false）在部分系统版本下会退化成只能
  /// 选中文件，改用「文件+目录」混合选择器；Linux 的 file_picker 走
  /// xdg-desktop-portal，部分系统（UOS/Deepin 等旧 portal 后端）会忽略
  /// directory 选项同样退化成只能选文件，改用 GTK 原生目录对话框
  /// （file_selector_linux）。两者之外仍用 file_picker 的目录选择器；
  /// 选中目录或其中任意模型文件都能归位到模型根目录。
  Future<void> chooseDirectory() async {
    // 内置模型位于应用包内，不作为选择器的初始目录
    final initial = (paths == null || paths!.bundled) ? null : paths!.dir;
    String? picked;
    if (Platform.isMacOS) {
      final picks = await FilePicker.pickFileAndDirectoryPaths(
        dialogTitle: '选择模型目录',
        initialDirectory: initial,
      );
      if (picks.isEmpty) return;
      // 混合选择器可多选：优先取选中的目录，全是文件时取第一个
      picked = picks.any((p) => Directory(p).existsSync())
          ? picks.firstWhere((p) => Directory(p).existsSync())
          : picks.first;
    } else if (Platform.isLinux) {
      try {
        picked = await file_selector.getDirectoryPath(
          initialDirectory: initial,
          confirmButtonText: '选择',
        );
      } on MissingPluginException {
        picked = await FilePicker.getDirectoryPath(
          dialogTitle: '选择模型目录',
          initialDirectory: initial,
        );
      }
    } else {
      picked = await FilePicker.getDirectoryPath(
        dialogTitle: '选择模型目录',
        initialDirectory: initial,
      );
    }
    if (picked == null) return;

    scanning = true;
    error = null;
    notifyListeners();

    paths = await _manager.resolveScan(picked);
    scanning = false;

    if (paths == null || !paths!.coreReady) {
      error = '该目录中未找到必需的模型文件（FireRedAsr2 / Silero VAD）';
    } else {
      await ModelManager.saveDir(paths!.dir);
    }
    notifyListeners();

    if (coreReady && !asrReady) await loadEngines();
  }

  /// 加载 ASR 引擎（FireRedAsr2 AED）。worker 数与线程数按设备算力
  /// 自动调节（线程数 4 封顶；仅核数与内存都大幅充裕时才启用第 2 个
  /// worker，取舍依据见 device_tuning.dart 的基准注释）。
  Future<void> loadEngines() async {
    if (loading || !coreReady || asrReady) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final tuning = await _deviceTuning();
      await asr.load(
        paths: paths!,
        workers: tuning.asrWorkers,
        numThreads: tuning.asrThreads,
      );
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
      final tuning = await _deviceTuning();
      await diarization.load(paths: paths!, numThreads: tuning.diarThreads);
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
