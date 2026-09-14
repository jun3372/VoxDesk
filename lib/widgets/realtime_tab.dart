import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../data/transcript_models.dart';
import '../services/history_service.dart';
import '../state/history_controller.dart';
import '../state/realtime_controller.dart';
import 'common.dart';
import 'player_bar.dart';
import 'transcript_view.dart';
import 'waveform.dart';

/// 「实时转写」Tab：就绪 / 录音中 / 已结束。
///
/// 录音中与已结束采用与「上传音频」Tab 相同的页面骨架：
/// 顶部内容卡片（随状态切换）+ 底部转写结果卡片。
class RealtimeTab extends StatelessWidget {
  const RealtimeTab({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<RealtimeController>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 20),
      child: ctrl.phase == RealtimePhase.idle
          ? _ReadyView(ctrl: ctrl)
          : Column(
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

  final RealtimeController ctrl;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(22),
      child: switch (ctrl.phase) {
        RealtimePhase.idle => const SizedBox.shrink(),
        RealtimePhase.recording => _RecordingBody(ctrl: ctrl),
        RealtimePhase.ended =>
          ctrl.retranscribing
              ? _RetranscribingBody(ctrl: ctrl)
              : _EndedBody(ctrl: ctrl),
      },
    );
  }
}

/// 录音中：会话卡 + 时长区 + 实时波形 + 暂停/结束。
class _RecordingBody extends StatelessWidget {
  const _RecordingBody({required this.ctrl});

  final RealtimeController ctrl;

  @override
  Widget build(BuildContext context) {
    final paused = ctrl.paused;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SessionCard(ctrl: ctrl),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Text(
              '录音时长',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              formatClock(ctrl.elapsedSec.toDouble()),
              style: const TextStyle(
                fontSize: 26,
                height: 1,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 14),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                ctrl.deviceName,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const Spacer(),
            StatusPill(
              label: paused ? '已暂停' : '录音中',
              background: paused ? AppColors.border : AppColors.successSoft,
              color: paused ? AppColors.textSecondary : AppColors.success,
              showDot: !paused,
            ),
          ],
        ),
        const SizedBox(height: 14),
        StaticWaveform(
          height: 48,
          peaks: List.of(ctrl.liveWave),
          color: paused ? AppColors.textSecondary : AppColors.primary,
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            SoftButton(
              label: paused ? '继续' : '暂停',
              icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              onPressed: paused ? ctrl.resume : ctrl.pause,
            ),
            const SizedBox(width: 10),
            PrimaryButton(
              label: '结束',
              icon: Icons.stop_rounded,
              onPressed: ctrl.saving ? null : ctrl.stop,
            ),
          ],
        ),
      ],
    );
  }
}

/// 重新转写中：会话卡 + 进度区（与上传页转写中布局一致）。
class _RetranscribingBody extends StatelessWidget {
  const _RetranscribingBody({required this.ctrl});

  final RealtimeController ctrl;

  @override
  Widget build(BuildContext context) {
    final percent = (ctrl.retranscribeProgress * 100).round();
    final paused = ctrl.retranscribePaused;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SessionCard(ctrl: ctrl, compact: true),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Text(
              '重新转写进度',
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
                '已用 ${formatDuration(ctrl.retranscribeElapsedSec.toDouble())}'
                '${ctrl.retranscribeEtaSec > 0 ? '  /  预计剩余 ${formatDuration(ctrl.retranscribeEtaSec.toDouble())}' : ''}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const Spacer(),
            StatusPill(
              label: paused
                  ? '已暂停'
                  : (ctrl.stageLabel.isEmpty ? '转写中' : ctrl.stageLabel),
              background: AppColors.primarySoft,
              color: AppColors.primary,
              icon: paused ? Icons.pause_rounded : Icons.sync_rounded,
            ),
          ],
        ),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: ctrl.retranscribeProgress,
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
              label: paused ? '继续' : '暂停',
              icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              onPressed: paused
                  ? ctrl.resumeRetranscribe
                  : ctrl.pauseRetranscribe,
            ),
            const SizedBox(width: 10),
            PrimaryButton(
              label: '结束',
              icon: Icons.stop_rounded,
              onPressed: ctrl.finishRetranscribe,
            ),
          ],
        ),
      ],
    );
  }
}

/// 已结束：会话卡 + 波形 + 字数 + 重新开始 / 重新转写。
class _EndedBody extends StatelessWidget {
  const _EndedBody({required this.ctrl});

  final RealtimeController ctrl;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SessionCard(
          ctrl: ctrl,
          trailing: const StatusPill(
            label: '已结束',
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
            const Spacer(),
            GhostButton(
              label: '重新开始',
              icon: Icons.refresh_rounded,
              onPressed: ctrl.retranscribing
                  ? null
                  : () {
                      // 开启新会话时同步取消侧边栏历史记录的选中态
                      context.read<HistoryController>().select(null);
                      ctrl.restart();
                    },
            ),
            const SizedBox(width: 8),
            SoftButton(
              label: '重新转写',
              icon: Icons.replay_rounded,
              onPressed: ctrl.canRetranscribe ? ctrl.retranscribe : null,
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 会话卡片（对应上传页的文件卡片）
// ---------------------------------------------------------------------------

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.ctrl, this.trailing, this.compact = false});

  final RealtimeController ctrl;
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
            child: const Icon(Icons.mic_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title(ctrl),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(height: 3),
                  Text(
                    _metaText(ctrl),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary.withValues(alpha: 0.95),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        ],
      ),
    );
  }

  String _title(RealtimeController ctrl) =>
      '实时录音 ${formatDateTime(ctrl.startedAt ?? DateTime.now())}';

  String _metaText(RealtimeController ctrl) {
    final parts = <String>[
      'WAV',
      if (ctrl.audioSizeBytes != null) formatFileSize(ctrl.audioSizeBytes!),
      formatDuration(
        ctrl.phase == RealtimePhase.recording
            ? ctrl.elapsedSec.toDouble()
            : ctrl.endedDurationSec,
      ),
      ctrl.deviceName,
    ];
    return parts.join('  ·  ');
  }
}

// ---------------------------------------------------------------------------
// 就绪
// ---------------------------------------------------------------------------

class _ReadyView extends StatelessWidget {
  const _ReadyView({required this.ctrl});

  final RealtimeController ctrl;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: AppCard(
          background: AppColors.primarySoftAlt,
          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: _MicCircle(onTap: ctrl.canStart ? ctrl.start : null),
              ),
              const SizedBox(height: 22),
              const Center(
                child: Text(
                  '准备开始实时转写',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (!ctrl.models.ready) ...[
                const SizedBox(height: 10),
                const Center(
                  child: Text(
                    '请先在左下角「加载模型」面板加载模型',
                    style: TextStyle(fontSize: 12.5, color: AppColors.primary),
                  ),
                ),
              ],
              if (ctrl.error != null) ...[
                const SizedBox(height: 10),
                Center(
                  child: Text(
                    ctrl.error!,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              const _DropdownCapsule(icon: Icons.mic_rounded, text: '系统默认麦克风'),
              const SizedBox(height: 10),
              const _DropdownCapsule(
                icon: Icons.tune_rounded,
                text: '音频设置：16 kHz · 单声道 · PCM',
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
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
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                    ),
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
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                    ),
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
                ],
              ),
              const SizedBox(height: 16),
              Center(
                child: PrimaryButton(
                  label: '开始实时转写',
                  icon: Icons.mic_rounded,
                  onPressed: ctrl.canStart ? ctrl.start : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 转写结果卡片
// ---------------------------------------------------------------------------

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.ctrl});

  final RealtimeController ctrl;

  @override
  Widget build(BuildContext context) {
    final hasResult = ctrl.segments.isNotEmpty;
    final playable =
        ctrl.phase == RealtimePhase.ended && ctrl.audioPath != null;
    final pending =
        (ctrl.recognizing && ctrl.phase == RealtimePhase.recording) ||
        (ctrl.retranscribing && !ctrl.retranscribePaused);
    final baseName =
        '实时转写_${formatDateTime(ctrl.startedAt ?? DateTime.now()).replaceAll(RegExp(r'[: ]'), '-')}';

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
                if (ctrl.phase == RealtimePhase.recording) ...[
                  const SizedBox(width: 10),
                  const StatusPill(
                    label: '实时转写中',
                    background: AppColors.successSoft,
                    color: AppColors.success,
                    showDot: true,
                  ),
                ],
                if (ctrl.phase == RealtimePhase.ended &&
                    hasResult &&
                    !ctrl.retranscribing) ...[
                  const SizedBox(width: 10),
                  const StatusPill(
                    label: '转写完成',
                    background: AppColors.successSoft,
                    color: AppColors.success,
                  ),
                ],
                if (ctrl.diarizing || ctrl.liveDiarizing) ...[
                  const SizedBox(width: 8),
                  const StatusPill(
                    label: '说话人标注中',
                    background: AppColors.primarySoft,
                    color: AppColors.primary,
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
                  onTap: ctrl.audioPath != null
                      ? () => exportAudio(context, baseName, ctrl.audioPath!)
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
                          createdAt: ctrl.startedAt,
                          durationSec: ctrl.endedDurationSec,
                        )
                      : null,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: hasResult
                  ? TranscriptListView(
                      segments: ctrl.segments,
                      pending: pending,
                      autoFollow: ctrl.recording || ctrl.retranscribing,
                      onTimestampTap: playable
                          ? (sec) => ctrl.seekRequest.value = sec
                          : null,
                      onSpeakerTap: ctrl.retranscribing
                          ? null
                          : (seg) => _renameSpeaker(context, ctrl, seg),
                    )
                  : ctrl.recognizing || ctrl.retranscribing
                  ? const TranscriptEmptyView(
                      title: '正在等待识别结果…',
                      subtitle: '语音内容会在几秒内显示在这里',
                    )
                  : const TranscriptEmptyView(
                      title: '开始说话后，识别的文字将实时显示在这里',
                      subtitle: '全部处理均在本地离线完成',
                    ),
            ),
          ),
          if (ctrl.phase == RealtimePhase.recording)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: const BoxDecoration(
                color: AppColors.cardWarm,
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(14),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.mic_rounded,
                    size: 14,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '当前输入：${ctrl.deviceName}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  const Text(
                    '本地实时处理 · 低延迟',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Text(
                    '16 kHz · PCM · 单声道',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          if (playable)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
              child: AudioPlayerBar(
                key: ValueKey(ctrl.audioPath),
                filePath: ctrl.audioPath!,
                totalSec: ctrl.endedDurationSec,
                seekRequest: ctrl.seekRequest,
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 小组件
// ---------------------------------------------------------------------------

class _MicCircle extends StatelessWidget {
  const _MicCircle({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    const size = 96.0;
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.18),
            blurRadius: 26,
            spreadRadius: 6,
          ),
        ],
      ),
      child: Material(
        color: AppColors.primarySoft,
        shape: const CircleBorder(
          side: BorderSide(color: AppColors.primaryBorder, width: 1.4),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(
              Icons.mic_rounded,
              size: size * 0.42,
              color: AppColors.primary,
            ),
          ),
        ),
      ),
    );
  }
}

class _DropdownCapsule extends StatelessWidget {
  const _DropdownCapsule({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.primary),
          const SizedBox(width: 7),
          Text(
            text,
            style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
          ),
          const SizedBox(width: 6),
          const Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 15,
            color: AppColors.textSecondary,
          ),
        ],
      ),
    );
  }
}

/// 弹出说话人重命名对话框并应用（作用于全文同一说话人）。
Future<void> _renameSpeaker(
  BuildContext context,
  RealtimeController ctrl,
  TranscriptSegment seg,
) async {
  if (seg.speaker == null) return;
  final name = await showSpeakerRenameDialog(context, segment: seg);
  if (name == null || !context.mounted) return;
  await ctrl.renameSpeaker(seg.speaker!, name);
}

class _IconAction extends StatelessWidget {
  const _IconAction({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = onTap == null
        ? AppColors.textSecondary.withValues(alpha: 0.5)
        : AppColors.textSecondary;
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
