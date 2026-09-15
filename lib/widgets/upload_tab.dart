import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../data/transcript_models.dart';
import '../services/history_service.dart';
import '../state/history_controller.dart';
import '../state/model_controller.dart';
import '../state/upload_controller.dart';
import 'common.dart';
import 'player_bar.dart';
import 'transcript_view.dart';
import 'waveform.dart';

/// 「上传音频」Tab：空状态 / 已选文件 / 转写中 / 转写完成。
class UploadTab extends StatelessWidget {
  const UploadTab({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<UploadController>();
    // canStart 依赖 models.ready：模型后台加载完成时本页不会收到
    // UploadController 的通知，需一并订阅 ModelController 刷新按钮态
    context.watch<ModelController>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TopCard(ctrl: ctrl),
          if (ctrl.error != null) ...[
            const SizedBox(height: 10),
            ErrorBanner(message: ctrl.error!),
          ],
          const SizedBox(height: 18),
          Expanded(child: _ResultCard(ctrl: ctrl)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 顶部内容卡片（随状态切换）
// ---------------------------------------------------------------------------

class _TopCard extends StatelessWidget {
  const _TopCard({required this.ctrl});

  final UploadController ctrl;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(22),
      background: ctrl.phase == UploadPhase.idle
          ? AppColors.primarySoftAlt
          : AppColors.card,
      child: switch (ctrl.phase) {
        UploadPhase.idle => const _Dropzone(),
        UploadPhase.fileSelected => _FileSelectedView(ctrl: ctrl),
        UploadPhase.transcribing => _TranscribingView(ctrl: ctrl),
        UploadPhase.done => _DoneView(ctrl: ctrl),
      },
    );
  }
}

/// 空状态：拖拽 / 选择文件。
class _Dropzone extends StatelessWidget {
  const _Dropzone();

  @override
  Widget build(BuildContext context) {
    final ctrl = context.read<UploadController>();

    return DropTarget(
      onDragEntered: (_) {},
      onDragExited: (_) {},
      onDragDone: (detail) {
        if (detail.files.isNotEmpty) {
          ctrl.setFile(detail.files.first.path);
        }
      },
      child: ctrl.preparingFile
          ? Container(
              padding: const EdgeInsets.symmetric(vertical: 60),
              child: const Column(
                children: [
                  CircularProgressIndicator(color: AppColors.primary),
                  SizedBox(height: 14),
                  Text(
                    '正在读取音频文件…',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            )
          : Container(
              padding: const EdgeInsets.symmetric(vertical: 44),
              decoration: BoxDecoration(
                color: AppColors.primarySoftAlt,
                borderRadius: BorderRadius.circular(14),
              ),
              child: CustomPaint(
                foregroundPainter: DashedRRectBorder(
                  radius: 14,
                  color: AppColors.primaryBorder,
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    const Icon(
                      Icons.cloud_upload_outlined,
                      size: 46,
                      color: AppColors.primary,
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      '选择音频文件或拖拽到这里',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '支持 WAV / MP3 / M4A / FLAC / OGG 格式',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 18),
                    PrimaryButton(
                      label: '选择音频文件',
                      icon: Icons.folder_open_rounded,
                      onPressed: ctrl.pickFile,
                    ),
                    const SizedBox(height: 18),
                  ],
                ),
              ),
            ),
    );
  }
}

/// 已选文件：文件卡 + 规范化选项 + 开始按钮。
class _FileSelectedView extends StatelessWidget {
  const _FileSelectedView({required this.ctrl});

  final UploadController ctrl;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FileCard(
          ctrl: ctrl,
          trailing: Row(
            children: [
              GhostButton(
                label: '更换文件',
                icon: Icons.swap_horiz_rounded,
                onPressed: ctrl.pickFile,
              ),
              const SizedBox(width: 8),
              SoftButton(
                label: '删除文件',
                icon: Icons.delete_outline_rounded,
                onPressed: ctrl.clearFile,
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            SizedBox(
              width: 20,
              child: Checkbox(
                value: ctrl.usePunctuation,
                activeColor: AppColors.primary,
                onChanged: (v) => ctrl.setUsePunctuation(v ?? false),
              ),
            ),
            const Text(
              '数字与标点规范化',
              style: TextStyle(fontSize: 13.5, color: AppColors.textPrimary),
            ),
            Tooltip(
              message: ctrl.models.punctuationAvailable
                  ? '使用本地标点恢复模型为识别结果添加标点'
                  : '未检测到标点恢复模型，可在模型目录中放入 punct-ct-transformer 模型后启用',
              child: const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(
                  Icons.info_outline,
                  size: 15,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 22),
            SizedBox(
              width: 20,
              child: Checkbox(
                value: ctrl.useDiarization,
                activeColor: AppColors.primary,
                onChanged: (v) => ctrl.setUseDiarization(v ?? false),
              ),
            ),
            const Text(
              '自动标注说话人',
              style: TextStyle(fontSize: 13.5, color: AppColors.textPrimary),
            ),
            Tooltip(
              message: ctrl.models.diarizationAvailable
                  ? '使用本地说话人分离模型自动区分不同说话人并标注标签'
                  : '未检测到说话人分离模型，可在模型目录中放入说话人分离模型后启用',
              child: const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(
                  Icons.info_outline,
                  size: 15,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const Spacer(),
            PrimaryButton(
              label: '开始转写',
              icon: Icons.arrow_forward_rounded,
              onPressed: ctrl.canStart ? ctrl.startTranscription : null,
            ),
          ],
        ),
        if (!ctrl.models.ready) ...[
          const SizedBox(height: 12),
          const _ModelNotReadyHint(),
        ],
      ],
    );
  }
}

/// 转写中：文件卡 + 进度区。
class _TranscribingView extends StatelessWidget {
  const _TranscribingView({required this.ctrl});

  final UploadController ctrl;

  @override
  Widget build(BuildContext context) {
    final percent = (ctrl.progress * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FileCard(ctrl: ctrl, compact: true),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Text(
              '转写进度',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '$percent%',
              style: const TextStyle(
                fontSize: 26,
                height: 1,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 14),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                '已用 ${formatDuration(ctrl.elapsedSec.toDouble())}'
                '${ctrl.etaSec > 0 ? '  /  预计剩余 ${formatDuration(ctrl.etaSec.toDouble())}' : ''}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const Spacer(),
            StatusPill(
              label: ctrl.paused
                  ? '已暂停'
                  : (ctrl.stageLabel.isEmpty ? '转写中' : ctrl.stageLabel),
              background: AppColors.primarySoft,
              color: AppColors.primary,
              icon: ctrl.paused ? Icons.pause_rounded : Icons.sync_rounded,
            ),
          ],
        ),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: ctrl.progress,
            minHeight: 8,
            backgroundColor: AppColors.primarySoft,
            valueColor: const AlwaysStoppedAnimation(AppColors.primary),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            SoftButton(
              label: ctrl.paused ? '继续' : '暂停',
              icon: ctrl.paused
                  ? Icons.play_arrow_rounded
                  : Icons.pause_rounded,
              onPressed: ctrl.paused ? ctrl.resume : ctrl.pause,
            ),
            const SizedBox(width: 10),
            PrimaryButton(
              label: '结束',
              icon: Icons.stop_rounded,
              onPressed: ctrl.finish,
            ),
          ],
        ),
      ],
    );
  }
}

/// 转写完成：文件卡 + 波形 + 字数 + 重新上传。
class _DoneView extends StatelessWidget {
  const _DoneView({required this.ctrl});

  final UploadController ctrl;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FileCard(
          ctrl: ctrl,
          trailing: const StatusPill(
            label: '转写完成',
            background: AppColors.successSoft,
            color: AppColors.success,
            icon: Icons.check_rounded,
          ),
        ),
        const SizedBox(height: 16),
        StaticWaveform(peaks: ctrl.peaks),
        const SizedBox(height: 12),
        Row(
          children: [
            Text.rich(
              TextSpan(
                text: '已识别 ',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
                children: [
                  TextSpan(
                    text: formatCount(ctrl.charCount),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const TextSpan(text: ' 个字符'),
                ],
              ),
            ),
            // 重新转写也走 useDiarization 开关（转写开始时快照），此处可随时勾选
            SizedBox(
              width: 20,
              child: Checkbox(
                value: ctrl.useDiarization,
                activeColor: AppColors.primary,
                onChanged: (v) => ctrl.setUseDiarization(v ?? false),
              ),
            ),
            const Text(
              '自动标注说话人',
              style: TextStyle(fontSize: 13.5, color: AppColors.textPrimary),
            ),
            Tooltip(
              message: ctrl.models.diarizationAvailable
                  ? '重新转写时使用本地说话人分离模型自动区分不同说话人并标注标签'
                  : '未检测到说话人分离模型，可在模型目录中放入说话人分离模型后启用',
              child: const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(
                  Icons.info_outline,
                  size: 15,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            GhostButton(
              label: '重新上传',
              icon: Icons.refresh_rounded,
              onPressed: () {
                // 回到空状态时同步取消侧边栏历史记录的选中态
                context.read<HistoryController>().select(null);
                ctrl.resetToIdle();
              },
            ),
            const SizedBox(width: 8),
            SoftButton(
              label: '重新转写',
              icon: Icons.replay_rounded,
              onPressed: ctrl.canStart ? ctrl.retranscribe : null,
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 文件卡片
// ---------------------------------------------------------------------------

class _FileCard extends StatelessWidget {
  const _FileCard({required this.ctrl, this.trailing, this.compact = false});

  final UploadController ctrl;
  final Widget? trailing;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.music_note_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ctrl.fileName ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _metaText(),
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textSecondary.withValues(alpha: 0.95),
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        ],
      ),
    );
  }

  String _metaText() {
    final parts = <String>[
      if (ctrl.fileSizeBytes != null) formatFileSize(ctrl.fileSizeBytes!),
      if (ctrl.fileName != null) ctrl.fileName!.split('.').last.toUpperCase(),
      if (ctrl.durationSec > 0) formatDuration(ctrl.durationSec),
    ];
    return parts.join('  ·  ');
  }
}

class _ModelNotReadyHint extends StatelessWidget {
  const _ModelNotReadyHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, size: 15, color: AppColors.primary),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '模型尚未加载：请先在左下角「加载模型」面板选择模型目录并加载。',
              style: TextStyle(fontSize: 12, color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 转写结果卡片
// ---------------------------------------------------------------------------

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.ctrl});

  final UploadController ctrl;

  @override
  Widget build(BuildContext context) {
    final hasResult = ctrl.segments.isNotEmpty;
    final audioPlayable =
        ctrl.phase == UploadPhase.done && ctrl.filePath != null;
    final baseName = (ctrl.fileName ?? '转写结果').replaceAll(
      RegExp(r'\.[a-zA-Z0-9]+$'),
      '',
    );

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 14, 12),
            child: Row(
              children: [
                const Icon(
                  Icons.description_rounded,
                  size: 19,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                const Text(
                  '转写结果',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (ctrl.phase == UploadPhase.done && hasResult) ...[
                  const SizedBox(width: 10),
                  const StatusPill(
                    label: '转写完成',
                    background: AppColors.successSoft,
                    color: AppColors.success,
                  ),
                ],
                const Spacer(),
                _IconAction(
                  icon: Icons.copy_rounded,
                  label: '复制',
                  onTap: hasResult
                      ? () => copyText(
                          context,
                          HistoryService.buildExportText(
                            ctrl.segments,
                            withSpeakers: true,
                          ),
                        )
                      : null,
                ),
                _IconAction(
                  icon: Icons.audio_file_rounded,
                  label: '导出音频',
                  onTap: ctrl.filePath != null
                      ? () => exportAudio(context, baseName, ctrl.filePath!)
                      : null,
                ),
                _IconAction(
                  icon: Icons.article_outlined,
                  label: '导出 DOCX',
                  onTap: hasResult
                      ? () => exportDocx(
                          context,
                          baseName,
                          ctrl.segments,
                          durationSec: ctrl.durationSec,
                        )
                      : null,
                ),
                _IconAction(
                  icon: Icons.delete_outline_rounded,
                  label: '清空',
                  danger: true,
                  onTap: hasResult ? ctrl.clearResult : null,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 0, 14),
              child: hasResult
                  ? TranscriptListView(
                      segments: ctrl.segments,
                      pending: ctrl.transcribing && !ctrl.paused,
                      autoFollow: ctrl.transcribing,
                      onTimestampTap: audioPlayable
                          ? (sec) => ctrl.seekRequest.value = sec
                          : null,
                      onSpeakerTap: ctrl.transcribing
                          ? null
                          : (seg) => _renameSpeaker(context, ctrl, seg),
                    )
                  : ctrl.transcribing
                  ? const TranscriptEmptyView(
                      title: '正在等待识别结果…',
                      subtitle: '语音内容会在几秒内显示在这里',
                    )
                  : const TranscriptEmptyView(),
            ),
          ),
          if (audioPlayable)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
              child: AudioPlayerBar(
                key: ValueKey(ctrl.filePath),
                filePath: ctrl.filePath!,
                totalSec: ctrl.durationSec,
                seekRequest: ctrl.seekRequest,
              ),
            ),
        ],
      ),
    );
  }
}

/// 弹出说话人重命名对话框并应用（作用于全文同一说话人）。
Future<void> _renameSpeaker(
  BuildContext context,
  UploadController ctrl,
  TranscriptSegment seg,
) async {
  if (seg.speaker == null) return;
  final name = await showSpeakerRenameDialog(context, segment: seg);
  if (name == null || !context.mounted) return;
  await ctrl.renameSpeaker(seg.speaker!, name);
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.label,
    this.onTap,
    this.danger = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = onTap == null
        ? AppColors.textSecondary.withValues(alpha: 0.5)
        : (danger ? AppColors.primary : AppColors.textSecondary);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 12, color: color)),
          ],
        ),
      ),
    );
  }
}
