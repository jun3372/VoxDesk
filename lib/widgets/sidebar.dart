import 'dart:ffi' hide Size;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../data/transcript_models.dart';
import '../state/history_controller.dart';
import '../state/model_controller.dart';
import 'common.dart';

/// 左侧栏：Logo / 历史记录 / 加载模型面板 / 环境信息。
class Sidebar extends StatelessWidget {
  const Sidebar({super.key, required this.onViewHistory});

  /// 点击历史条目回调。
  final void Function(HistoryItem item) onViewHistory;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 292,
      decoration: const BoxDecoration(
        color: AppColors.cardWarm,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Logo(),
          const Divider(height: 1, indent: 20, endIndent: 20),
          const _HistoryHeader(),
          Expanded(
            child: Consumer<HistoryController>(
              builder: (context, history, _) {
                if (history.items.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      '暂无历史记录，完成一次转写后会自动保存在这里。',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 2,
                  ),
                  itemCount: history.items.length,
                  itemBuilder: (context, i) {
                    final item = history.items[i];
                    return _HistoryTile(
                      item: item,
                      selected: history.selectedId == item.id,
                      onTap: () {
                        history.select(item.id);
                        onViewHistory(item);
                      },
                      onDelete: () => history.remove(item),
                    );
                  },
                );
              },
            ),
          ),
          const _ModelPanel(),
          const _EnvFooter(),
        ],
      ),
    );
  }
}

/// macOS 透明标题栏下，左上角交通灯按钮占用的顶部安全区高度。
const double _kMacTrafficLightInset = 28;

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20 + (Platform.isMacOS ? _kMacTrafficLightInset : 0),
        20,
        14,
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.graphic_eq_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '离线语音工作台',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 2),
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
        ],
      ),
    );
  }
}

class _HistoryHeader extends StatelessWidget {
  const _HistoryHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
      child: Row(
        children: [
          const Text(
            '历史记录',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: () => context.read<HistoryController>().reload(),
            icon: const Icon(Icons.refresh_rounded, size: 15),
            label: const Text('刷新', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.onDelete,
  });

  final HistoryItem item;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ext = item.title.contains('.')
        ? item.title.split('.').last.toLowerCase()
        : 'rec';
    final color = item.type == HistoryType.realtime
        ? const Color(0xFF7C5CFF)
        : AppColors.fileIcon(ext);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? AppColors.primarySoft : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    item.type == HistoryType.realtime
                        ? Icons.mic_rounded
                        : Icons.description_rounded,
                    size: 16,
                    color: color,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${formatDateTime(item.createdAt)}'
                        '  ·  ${formatDuration(item.durationSec)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: AppColors.textSecondary.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 26,
                  height: 26,
                  child: IconButton(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded, size: 15),
                    color: AppColors.textSecondary,
                    tooltip: '删除记录',
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 底部「加载模型」面板。
class _ModelPanel extends StatefulWidget {
  const _ModelPanel();

  @override
  State<_ModelPanel> createState() => _ModelPanelState();
}

class _ModelPanelState extends State<_ModelPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<ModelController>(
      builder: (context, models, _) {
        final ready = models.asrReady;
        final pill = ready
            ? const StatusPill(
                label: '已就绪',
                background: AppColors.successSoft,
                color: AppColors.success,
              )
            : StatusPill(
                label: models.loading ? '加载中' : '未加载',
                background: AppColors.primarySoft,
                color: AppColors.primary,
              );

        return Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.primarySoftAlt,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Row(
                  children: [
                    const Icon(
                      Icons.layers_rounded,
                      size: 18,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      '加载模型',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    pill,
                    const Spacer(),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedCrossFade(
                crossFadeState: _expanded
                    ? CrossFadeState.showFirst
                    : CrossFadeState.showSecond,
                duration: const Duration(milliseconds: 200),
                firstChild: const SizedBox(width: double.infinity),
                secondChild: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _ExpandedBody(models: models),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ExpandedBody extends StatelessWidget {
  const _ExpandedBody({required this.models});

  final ModelController models;

  @override
  Widget build(BuildContext context) {
    final p = models.paths;

    String? dirText;
    if (models.scanning) {
      dirText = '正在扫描模型目录…';
    } else if (p == null) {
      dirText = '尚未找到模型目录';
    } else if (p.bundled) {
      dirText = '内置模型（随应用打包，无需选择目录）';
    } else {
      dirText = p.dir;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.folder_outlined,
              size: 14,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Tooltip(
                message: dirText,
                child: Text(
                  dirText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            InkWell(
              onTap: models.scanning
                  ? null
                  : () => context.read<ModelController>().chooseDirectory(),
              borderRadius: BorderRadius.circular(6),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  '选择',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _ModelCheckRow(
          label: 'FireRedAsr2 AED（语音识别）',
          ok: p?.asrReady ?? false,
        ),
        _ModelCheckRow(label: 'Silero VAD', ok: p?.vadReady ?? false),
        _ModelCheckRow(
          label: 'Pyannote 分割',
          ok: p?.pyannoteSegmentation.isNotEmpty ?? false,
        ),
        _ModelCheckRow(
          label: '3D-Speaker 嵌入',
          ok: p?.speakerEmbedding.isNotEmpty ?? false,
        ),
        _ModelCheckRow(
          label: '标点恢复（可选）',
          ok: p?.punctuationReady ?? false,
          optional: true,
        ),
        if (models.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              models.error!,
              style: const TextStyle(fontSize: 11, color: AppColors.primary),
            ),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: PrimaryButton(
                label: models.loading ? '加载中…' : '加载模型',
                icon: Icons.play_arrow_rounded,
                onPressed: models.loading || !models.coreReady
                    ? null
                    : () => models.loadEngines(),
              ),
            ),
            const SizedBox(width: 8),
            GhostButton(
              label: '停止',
              icon: Icons.stop_rounded,
              onPressed: models.asrReady ? () => models.releaseEngines() : null,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          models.usingBundled
              ? '模型已随应用内置，开箱即用'
              : '模型下载：见项目 docs/MODELS.md',
          style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _ModelCheckRow extends StatelessWidget {
  const _ModelCheckRow({
    required this.label,
    required this.ok,
    this.optional = false,
  });

  final String label;
  final bool ok;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    final color = ok
        ? AppColors.success
        : (optional ? AppColors.textSecondary : AppColors.primary);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        children: [
          Icon(
            ok
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EnvFooter extends StatelessWidget {
  const _EnvFooter();

  @override
  Widget build(BuildContext context) {
    final os = Platform.isMacOS
        ? 'macOS'
        : Platform.isWindows
        ? 'Windows'
        : 'Linux';
    final arch = switch (Abi.current()) {
      Abi.macosArm64 ||
      Abi.iosArm64 ||
      Abi.androidArm64 ||
      Abi.linuxArm64 => 'ARM64',
      Abi.macosX64 || Abi.windowsX64 || Abi.linuxX64 => 'x64',
      _ => Platform.version,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
      child: Row(
        children: [
          Text(
            '$os $arch',
            style: TextStyle(
              fontSize: 10.5,
              color: AppColors.textSecondary.withValues(alpha: 0.8),
            ),
          ),
          const Spacer(),
          Text(
            'CPU',
            style: TextStyle(
              fontSize: 10.5,
              color: AppColors.textSecondary.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}
