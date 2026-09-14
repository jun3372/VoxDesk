import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../core/theme.dart';

/// Windows / Linux 的应用内标题栏覆盖层：
/// 顶部整条为窗口拖拽区（双击切换最大化），右上角保留
/// 最小化 / 最大化 / 全屏 / 关闭按钮。
/// macOS 使用原生透明标题栏 + 交通灯按钮，不启用此组件。
class TitleBarOverlay extends StatefulWidget {
  const TitleBarOverlay({super.key});

  static final bool enabled =
      !kIsWeb && (Platform.isWindows || Platform.isLinux);

  /// 拖拽条与窗口按钮的高度。
  static const double barHeight = 40;

  /// 右上角窗口按钮的总宽度（页眉右侧需预留等宽安全区）。
  static const double controlsWidth = 44 * 4;

  @override
  State<TitleBarOverlay> createState() => _TitleBarOverlayState();
}

class _TitleBarOverlayState extends State<TitleBarOverlay> with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  Future<void> _toggleFullScreen() async {
    if (await windowManager.isFullScreen()) {
      await windowManager.setFullScreen(false);
    } else {
      await windowManager.setFullScreen(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: TitleBarOverlay.barHeight,
      child: Row(
        children: [
          Expanded(child: DragToMoveArea(child: const SizedBox.expand())),
          _WindowButton(
            icon: Icons.minimize_rounded,
            tooltip: '最小化',
            onTap: () => windowManager.minimize(),
          ),
          _WindowButton(
            icon: _maximized
                ? Icons.filter_none_rounded
                : Icons.crop_square_rounded,
            iconSize: 15,
            tooltip: _maximized ? '还原' : '最大化',
            onTap: _toggleMaximize,
          ),
          _WindowButton(
            icon: Icons.fullscreen_rounded,
            iconSize: 18,
            tooltip: '全屏',
            onTap: _toggleFullScreen,
          ),
          _WindowButton(
            icon: Icons.close_rounded,
            tooltip: '关闭',
            onTap: () => windowManager.close(),
            danger: true,
          ),
        ],
      ),
    );
  }
}

/// 单个窗口控制按钮：透明底，悬停浅灰底；关闭键悬停红底白字。
class _WindowButton extends StatefulWidget {
  const _WindowButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.iconSize = 16,
    this.danger = false,
  });

  final IconData icon;
  final String tooltip;
  final Future<void> Function() onTap;
  final double iconSize;
  final bool danger;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bg = _hover
        ? (widget.danger ? const Color(0xFFE5474D) : AppColors.border)
        : Colors.transparent;
    final fg = _hover && widget.danger ? Colors.white : AppColors.textSecondary;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onTap(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 44,
            height: double.infinity,
            color: bg,
            child: Icon(widget.icon, size: widget.iconSize, color: fg),
          ),
        ),
      ),
    );
  }
}
