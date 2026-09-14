import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'services/history_service.dart';
import 'state/history_controller.dart';
import 'state/model_controller.dart';
import 'state/realtime_controller.dart';
import 'state/upload_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    // 每个 isolate 都需要各自初始化原生绑定（worker isolate 内亦然）
    sherpa.initBindings();
  }

  // Windows / Linux：隐藏原生标题栏，窗口控制按钮由应用内 TitleBarOverlay
  // 提供（macOS 走原生透明标题栏 + 交通灯，见 MainFlutterWindow.swift）
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(1280, 800),
      minimumSize: Size(980, 640),
      center: true,
      title: '离线语音工作台',
      titleBarStyle: TitleBarStyle.hidden,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  final historyService = await HistoryService.create();

  final models = ModelController();
  final history = HistoryController(historyService);
  final upload = UploadController(models: models, history: historyService);
  final realtime = RealtimeController(models: models, history: historyService);
  // 转写历史写入完成后：刷新侧边栏列表并激活最新记录
  void onHistorySaved(String historyId) {
    history.select(historyId);
    history.reload();
  }

  realtime.onHistorySaved = onHistorySaved;
  upload.onHistorySaved = onHistorySaved;

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: models),
        ChangeNotifierProvider.value(value: history),
        ChangeNotifierProvider.value(value: upload),
        ChangeNotifierProvider.value(value: realtime),
      ],
      child: const VoxDesk(),
    ),
  );

  // 后台初始化：扫描/自动加载模型 + 载入历史
  models.init();
  history.reload();
}
