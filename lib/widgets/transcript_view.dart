import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../data/transcript_models.dart';

/// 转写结果列表：时间戳胶囊 + 可选说话人标签 + 正文。
/// 传入 [onTimestampTap] 后时间戳可点击（用于音频跳转到对应位置）。
/// 传入 [onSpeakerTap] 后说话人标签可点击（用于修改说话人名称）。
/// [autoFollow] 为 true 时，新段落写入后自动滚动到最后一行
/// （用户主动上滑阅读时暂停跟随，翻回底部后恢复）。
class TranscriptListView extends StatefulWidget {
  const TranscriptListView({
    super.key,
    required this.segments,
    this.pending = false,
    this.controller,
    this.onTimestampTap,
    this.onSpeakerTap,
    this.autoFollow = false,
  });

  final List<TranscriptSegment> segments;

  /// 是否显示“正在转写”高亮占位行。
  final bool pending;
  final ScrollController? controller;

  /// 点击时间戳回调（参数为该段起始秒）；null 时时间戳不可点击。
  final void Function(double startSec)? onTimestampTap;

  /// 点击说话人标签回调（参数为被点击的段）；null 时标签不可点击。
  final void Function(TranscriptSegment segment)? onSpeakerTap;

  /// 是否处于转写进行中（新段落持续写入）。
  final bool autoFollow;

  @override
  State<TranscriptListView> createState() => _TranscriptListViewState();
}

class _TranscriptListViewState extends State<TranscriptListView> {
  /// 距底部不超过该距离视为「正在跟随最新内容」。
  static const _nearBottomSlack = 160.0;

  ScrollController? _ownController;
  var _lastCount = 0;

  ScrollController get _scrollController =>
      widget.controller ?? (_ownController ??= ScrollController());

  @override
  void initState() {
    super.initState();
    _lastCount = widget.segments.length;
  }

  @override
  void didUpdateWidget(covariant TranscriptListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final count = widget.segments.length;
    final grew = count > _lastCount;
    _lastCount = count;
    if (!grew || !widget.autoFollow) return;

    // 新段落此帧尚未完成布局，用当前（旧）滚动位置判断
    // 用户是否停留在底部；停留在历史位置则不干扰阅读。
    final c = _scrollController;
    final wasNearBottom =
        !c.hasClients ||
        c.position.maxScrollExtent - c.position.pixels < _nearBottomSlack;
    if (!wasNearBottom) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !c.hasClients) return;
      c.animateTo(
        c.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _ownController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: widget.segments.length + (widget.pending ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        if (index == widget.segments.length) {
          return const _PendingRow();
        }
        return _SegmentRow(
          widget.segments[index],
          onTimestampTap: widget.onTimestampTap,
          onSpeakerTap: widget.onSpeakerTap,
        );
      },
    );
  }
}

class _SegmentRow extends StatelessWidget {
  const _SegmentRow(this.segment, {this.onTimestampTap, this.onSpeakerTap});

  final TranscriptSegment segment;
  final void Function(double startSec)? onTimestampTap;
  final void Function(TranscriptSegment segment)? onSpeakerTap;

  @override
  Widget build(BuildContext context) {
    final speaker = segment.speaker;
    final timestamp = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        formatClock(segment.startSec),
        style: const TextStyle(
          fontSize: 11.5,
          color: AppColors.primary,
          fontWeight: FontWeight.w600,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
    final speakerChip = speaker == null
        ? null
        : Tooltip(
            message: '点击修改说话人名称',
            child: InkWell(
              onTap: onSpeakerTap == null ? null : () => onSpeakerTap!(segment),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.primaryBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      segment.speakerLabel,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (onSpeakerTap != null) ...[
                      const SizedBox(width: 3),
                      const Icon(
                        Icons.edit_rounded,
                        size: 10.5,
                        color: AppColors.primary,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        onTimestampTap == null
            ? timestamp
            : Tooltip(
                message: '播放此段录音',
                child: InkWell(
                  onTap: () => onTimestampTap!(segment.startSec),
                  borderRadius: BorderRadius.circular(6),
                  child: timestamp,
                ),
              ),
        const SizedBox(width: 10),
        if (speakerChip != null) ...[speakerChip, const SizedBox(width: 8)],
        Expanded(
          child: SelectableText(
            segment.text,
            style: const TextStyle(
              fontSize: 14,
              height: 1.7,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

/// 修改说话人名称对话框：作用于全部该说话人的段落。
/// 输入留空保存 = 恢复默认标签「说话人 N」。
Future<String?> showSpeakerRenameDialog(
  BuildContext context, {
  required TranscriptSegment segment,
}) {
  final controller = TextEditingController(text: segment.speakerName ?? '');
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        '修改「${segment.speakerLabel}」的名称',
        style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
      ),
      contentPadding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            autofocus: true,
            maxLength: 20,
            decoration: const InputDecoration(
              hintText: '例如：张三、主持人、客户',
              counterText: '',
              isDense: true,
            ),
            onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
          ),
          const SizedBox(height: 6),
          const Text(
            '名称将应用到全文中同一位说话人的所有段落；留空保存则恢复默认标签。',
            style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          child: const Text('保存'),
        ),
      ],
    ),
  );
}

/// 录音/转写进行中的占位高亮行。
class _PendingRow extends StatefulWidget {
  const _PendingRow();

  @override
  State<_PendingRow> createState() => _PendingRowState();
}

class _PendingRowState extends State<_PendingRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          FadeTransition(
            opacity: Tween(begin: 0.25, end: 1.0).animate(_blink),
            child: Container(width: 2, height: 16, color: AppColors.primary),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              '目前正在实时转写，语音内容会在几秒内显示在这里…',
              style: TextStyle(
                fontSize: 13.5,
                color: AppColors.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 转写结果为空时的占位插画文案。
class TranscriptEmptyView extends StatelessWidget {
  const TranscriptEmptyView({
    super.key,
    this.title = '上传音频文件并开始转写后，文字结果将在这里显示',
    this.subtitle = '支持中、英及多种语言的高精度语音识别',
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    // 可滚动 + minHeight 兜底：高度受限（小窗口/测试视口）时可滚动，不溢出
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: h.isFinite && h > 0 ? h : 0),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          color: AppColors.primarySoft,
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      const Icon(
                        Icons.article_outlined,
                        size: 40,
                        color: AppColors.primaryBorder,
                      ),
                      Positioned(
                        right: 10,
                        bottom: 10,
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.card,
                              width: 2.5,
                            ),
                          ),
                          child: const Icon(
                            Icons.graphic_eq,
                            size: 11,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
