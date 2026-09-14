import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 应用数据根目录名（位于系统文档目录下）：历史记录、模型选择配置与
/// 默认模型目录都放在这里。
const dataDirName = 'VoxDesk';

/// 旧版本代号对应的数据目录名；启动时若存在则整体迁移到 [dataDirName]。
const legacyDataDirName = 'asrapp';

/// 文档目录下的应用数据根目录；首次调用时把旧代号目录迁移过来，
/// 保证升级前保存的历史记录与配置继续可见。
Future<Directory> appDataDir() async {
  final docs = await getApplicationDocumentsDirectory();
  final current = Directory(
    '${docs.path}${Platform.pathSeparator}$dataDirName',
  );
  final legacy = Directory(
    '${docs.path}${Platform.pathSeparator}$legacyDataDirName',
  );
  if (!current.existsSync() && legacy.existsSync()) {
    try {
      await legacy.rename(current.path);
    } catch (_) {
      // 迁移失败（如跨卷 rename 不支持）时放弃迁移：继续用新目录，
      // 旧目录原样保留，不覆盖、不删除。
    }
  }
  return current;
}
