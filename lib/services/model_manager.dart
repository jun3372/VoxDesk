import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_data.dart';

/// 扫描出的模型文件路径集合（空字符串表示缺失）。
class ModelPaths {
  const ModelPaths({
    required this.dir,
    this.encoder = '',
    this.decoder = '',
    this.tokens = '',
    this.sileroVad = '',
    this.pyannoteSegmentation = '',
    this.speakerEmbedding = '',
    this.punctuation = '',
    this.bundled = false,
  });

  final String dir;
  final String encoder;
  final String decoder;
  final String tokens;
  final String sileroVad;
  final String pyannoteSegmentation;
  final String speakerEmbedding;
  final String punctuation;

  /// 是否来自随应用打包的内置模型（bundle 内，而非用户选择的目录）。
  final bool bundled;

  bool get asrReady =>
      encoder.isNotEmpty && decoder.isNotEmpty && tokens.isNotEmpty;
  bool get vadReady => sileroVad.isNotEmpty;
  bool get diarizationReady =>
      pyannoteSegmentation.isNotEmpty && speakerEmbedding.isNotEmpty;
  bool get punctuationReady => punctuation.isNotEmpty;

  bool get coreReady => asrReady && vadReady;
  bool get allCoreReady => coreReady && diarizationReady;

  /// 是否至少匹配到一个模型文件（用于归位扫描时判断值得继续向上回溯）。
  bool get matchedAny =>
      asrReady || vadReady || diarizationReady || punctuationReady;
}

/// 模型目录扫描与默认位置管理。
///
/// 目录结构宽容处理：兼容 tarball 解包后的嵌套目录（如
/// `models/sherpa-onnx-fire-red-asr2-zh_en-int8-2026-02-26/encoder.int8.onnx`），
/// 通过文件名特征递归匹配。
class ModelManager {
  static const expectedLayout = [
    ('FireRedAsr2 AED', 'encoder.int8.onnx / decoder.int8.onnx / tokens.txt'),
    ('Silero VAD', 'silero_vad.onnx'),
    ('Pyannote 分离', 'pyannote_segmentation-3.0 / model.onnx'),
    (
      '3D-Speaker 嵌入',
      '3dspeaker_speech_eres2net_base_sv_zh-cn_3dspeaker_16k.onnx',
    ),
    ('标点恢复（可选）', 'sherpa-onnx-punct-ct-transformer-zh-en / model.onnx'),
  ];

  /// 默认模型目录：<文档目录>/VoxDesk/models。
  static Future<Directory> defaultDir() async {
    final dataDir = await appDataDir();
    return Directory('${dataDir.path}${Platform.pathSeparator}models');
  }

  /// 内置模型目录的候选路径（构建时由 scripts/bundle_models.sh 拷入）。
  ///
  /// 布局随产物形态：
  /// - Linux/Windows bundle：`<可执行文件目录>/data/models`
  /// - macOS .app：`<Contents>/Resources/models`
  static List<String> bundledCandidates(String exePath, {bool? isMacOS}) {
    final macOS = isMacOS ?? Platform.isMacOS;
    final exeDir = File(exePath).parent.path;
    if (macOS) {
      final contents = File(exeDir).parent.path; // .../Contents/MacOS -> Contents
      return ['$contents/Resources/models'];
    }
    return ['$exeDir/data/models'];
  }

  /// 已打包进应用的内置模型目录；不存在时返回 null。
  static String? bundledDir({bool? isMacOS}) {
    for (final dir in bundledCandidates(
      Platform.resolvedExecutable,
      isMacOS: isMacOS,
    )) {
      if (Directory(dir).existsSync()) return dir;
    }
    return null;
  }

  /// 扫描随应用打包的内置模型；无内置模型时返回 null。
  Future<ModelPaths?> scanBundled({bool? isMacOS}) async {
    final dir = ModelManager.bundledDir(isMacOS: isMacOS);
    if (dir == null) return null;
    return scan(dir, bundled: true);
  }

  /// 递归扫描 [dir]，返回匹配到的模型路径；关键文件缺失时返回的
  /// [ModelPaths] 对应字段为空字符串。[bundled] 标记来源为应用内置模型。
  Future<ModelPaths?> scan(String dirPath, {bool bundled = false}) async {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return null;

    String? encoder;
    String? decoder;
    String? tokens;
    String? silero;
    String? pyannote;
    String? embedding;
    String? punct;

    try {
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (e is! File) continue;
        final name = e.uri.pathSegments.last.toLowerCase();
        // 模型目录若从 Mac 拷贝会混入 AppleDouble（._*）、.DS_Store 等隐藏
        // 元数据文件，名字与真模型相同，被匹配到会让 onnxruntime 解析失败
        // 直接 abort（Protobuf parsing failed → core dump），一律跳过。
        if (name.startsWith('.')) continue;
        final path = e.path;

        switch (name) {
          case 'encoder.int8.onnx':
          case 'encoder.onnx':
            final p = path.toLowerCase();
            if (p.contains('fire') || p.contains('asr')) {
              encoder ??= path;
            }
          case 'decoder.int8.onnx':
          case 'decoder.onnx':
            final p = path.toLowerCase();
            if (p.contains('fire') || p.contains('asr')) {
              decoder ??= path;
            }
          case 'tokens.txt':
            tokens ??= path;
          case 'silero_vad.onnx':
            silero ??= path;
          case 'model.onnx' || 'model.int8.onnx':
            final p = path.toLowerCase();
            if (p.contains('pyannote') || p.contains('segmentation')) {
              pyannote ??= path;
            } else if (p.contains('punct') || p.contains('ct-transformer')) {
              punct ??= path;
            }
        }

        final lower = name;
        if ((lower.contains('3dspeaker') || lower.contains('eres2net')) &&
            lower.endsWith('.onnx')) {
          embedding ??= path;
        }
        if (lower.contains('punct') &&
            lower.contains('ct-transformer') &&
            lower.endsWith('.onnx')) {
          punct ??= path;
        }
      }
    } on FileSystemException catch (e) {
      // 目录不可读（如 macOS 沙盒下已保存的外部目录）时按缺失处理，
      // 交由上层回退到默认目录并提示用户重新选择。
      debugPrint('扫描模型目录失败: $dirPath, $e');
      return null;
    }

    // tokens.txt 与 encoder 保持就近：若 tokens 不在 encoder 同目录，
    // 尝试在 encoder 所在目录重新查找。
    if (encoder != null) {
      final sibling = File(
        '${File(encoder).parent.path}${Platform.pathSeparator}tokens.txt',
      );
      if (sibling.existsSync()) tokens = sibling.path;
    }

    final paths = ModelPaths(
      dir: dirPath,
      encoder: encoder ?? '',
      decoder: decoder ?? '',
      tokens: tokens ?? '',
      sileroVad: silero ?? '',
      pyannoteSegmentation: pyannote ?? '',
      speakerEmbedding: embedding ?? '',
      punctuation: punct ?? '',
      bundled: bundled,
    );
    return paths;
  }

  /// 归位扫描：从 [startPath]（目录或单个模型文件）出发找到模型根目录。
  ///
  /// 选择对话框在部分平台/系统版本下会返回文件路径，或用户选中了深层
  /// 子目录中的模型文件：此时从文件所在目录开始；若关键模型不全，向上
  /// 回溯最多 [maxUpLevels] 级，取第一个核心齐备的祖先目录；都找不到时
  /// 返回最深一层（起始目录）的扫描结果，便于界面展示已匹配到的部分。
  Future<ModelPaths?> resolveScan(String startPath, {int maxUpLevels = 4}) async {
    var dir = Directory(startPath);
    if (!dir.existsSync()) dir = dir.parent;

    var best = await scan(dir.path);
    if (best != null && best.coreReady) return best;

    // 当前层毫无模型特征时不再向上回溯，避免误选无关文件后
    // 把用户目录甚至整个磁盘递归扫一遍
    var cur = dir;
    for (var depth = 0; depth < maxUpLevels; depth++) {
      if (best == null || !best.matchedAny) break;
      final parent = cur.parent;
      if (parent.path == cur.path || _isRootLikePath(parent.path)) break;
      final up = await scan(parent.path);
      if (up == null) break; // 祖先目录不存在/不可读，停止回溯
      cur = parent;
      if (up.coreReady) return up;
      best = up;
    }
    return best;
  }

  /// 递归扫描这类路径代价过高（等于扫整个磁盘/所有挂载卷），回溯时跳过。
  static bool _isRootLikePath(String path) {
    if (path.isEmpty || path == '/' || path == '/Volumes') return true;
    if (Platform.isWindows) {
      return RegExp(r'^(?:[A-Za-z]:\\?|\\\\[^\\]+\\?)$').hasMatch(path);
    }
    return false;
  }

  /// 应用配置（记住上次选择的模型目录）。
  static Future<File> _configFile() async {
    final dataDir = await appDataDir();
    return File('${dataDir.path}${Platform.pathSeparator}config.json');
  }

  static Future<String?> loadSavedDir() async {
    try {
      final f = await _configFile();
      if (!f.existsSync()) return null;
      final content = await f.readAsString();
      final dir = content.trim();
      return dir.isEmpty ? null : dir;
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveDir(String dir) async {
    try {
      final f = await _configFile();
      await f.parent.create(recursive: true);
      await f.writeAsString(dir);
    } catch (e) {
      debugPrint('保存模型目录配置失败: $e');
    }
  }
}
