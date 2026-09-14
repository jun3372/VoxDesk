import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:voxdesk/app.dart';
import 'package:voxdesk/services/history_service.dart';
import 'package:voxdesk/state/history_controller.dart';
import 'package:voxdesk/state/model_controller.dart';
import 'package:voxdesk/state/realtime_controller.dart';
import 'package:voxdesk/state/upload_controller.dart';

void main() {
  testWidgets('主页面渲染与 Tab 切换冒烟测试', (tester) async {
    // 注意：testWidgets 内不能 await 真实异步 I/O（FakeAsync 环境下永不完成），
    // 必须使用同步的 createTempSync。
    final tempDir = Directory.systemTemp.createTempSync('voxdesk_history_test');
    addTearDown(() => tempDir.delete(recursive: true));

    // 桌面应用：使用接近真实窗口的逻辑尺寸（默认 800x600 太小）
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.reset);

    final historyService = HistoryService(tempDir);
    final models = ModelController();
    final history = HistoryController(historyService);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: models),
          ChangeNotifierProvider.value(value: history),
          ChangeNotifierProvider.value(
            value: UploadController(models: models, history: historyService),
          ),
          ChangeNotifierProvider.value(
            value: RealtimeController(models: models, history: historyService),
          ),
        ],
        child: const VoxDesk(),
      ),
    );
    await tester.pump();

    expect(find.text('语音转写'), findsNothing);
    // 侧边栏 Logo 显示统一的项目名称（页眉及其徽章已注释）
    expect(find.text('离线语音工作台'), findsOneWidget);
    expect(find.text('上传音频'), findsOneWidget);
    expect(find.text('实时转写'), findsOneWidget);
    expect(find.text('选择音频文件或拖拽到这里'), findsOneWidget);

    await tester.tap(find.text('实时转写'));
    await tester.pump();
    expect(find.text('准备开始实时转写'), findsOneWidget);
  });
}
