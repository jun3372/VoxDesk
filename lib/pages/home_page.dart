import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../data/transcript_models.dart';
import '../state/history_controller.dart';
import '../state/realtime_controller.dart';
import '../state/upload_controller.dart';
import '../widgets/common.dart';
import '../widgets/realtime_tab.dart';
import '../widgets/sidebar.dart';
import '../widgets/title_bar.dart';
import '../widgets/upload_tab.dart';

/// 应用主页面：左侧栏 + 右侧内容区（头部 / Tab / 内容）。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;

  Future<void> _openHistoryItem(HistoryItem item) async {
    final history = context.read<HistoryController>();
    final segs = await history.loadSegments(item);
    if (!mounted) return;

    // 先切 Tab 立即响应点击；viewHistory 内部会先渲染正文，
    // 波形等耗时部分后台补算，不阻塞切换。
    setState(() => _tab = item.type == HistoryType.file ? 0 : 1);
    if (item.type == HistoryType.file) {
      await context.read<UploadController>().viewHistory(item, segs);
    } else {
      await context.read<RealtimeController>().viewHistory(item, segs);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Windows / Linux：透明标题栏覆盖在内容之上，主体内容与标题栏融为一体
      body: Stack(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Sidebar(onViewHistory: _openHistoryItem),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: 22),
                    // const _Header(),
                    _Tabs(tab: _tab, onSelect: (i) => setState(() => _tab = i)),
                    Expanded(
                      child: _tab == 0
                          ? const UploadTab(key: ValueKey('upload'))
                          : const RealtimeTab(key: ValueKey('realtime')),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (TitleBarOverlay.enabled)
            const Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: TitleBarOverlay(),
            ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '离线语音工作台',
                  style: TextStyle(
                    fontSize: 26,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  '高精度 · 本地处理 · 数据更安全',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const OfflineBadge(),
        ],
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.tab, required this.onSelect});

  final int tab;
  final void Function(int) onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 14, 28, 0),
      child: Row(
        children: [
          _TabItem(
            icon: Icons.upload_file_rounded,
            label: '上传音频',
            active: tab == 0,
            onTap: () => onSelect(0),
          ),
          const SizedBox(width: 30),
          _TabItem(
            icon: Icons.mic_none_rounded,
            label: '实时转写',
            active: tab == 1,
            onTap: () => onSelect(1),
          ),
        ],
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.primary : AppColors.textSecondary;
    return InkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Column(
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Container(
              width: 56,
              height: 3,
              decoration: BoxDecoration(
                color: active ? AppColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
