import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../data/transcript_models.dart';
import '../services/docx_exporter.dart';

/// 底部音频播放条：播放/暂停、进度、音量、倍速。
/// 传入 [seekRequest] 后可响应「点击转写时间戳跳转」请求。
class AudioPlayerBar extends StatefulWidget {
  const AudioPlayerBar({
    super.key,
    required this.filePath,
    required this.totalSec,
    this.seekRequest,
  });

  final String filePath;
  final double totalSec;

  /// 跳转请求（单位秒）：置值后播放条 seek 到该位置并开始播放，消费后置回 null。
  final ValueNotifier<double?>? seekRequest;

  @override
  State<AudioPlayerBar> createState() => _AudioPlayerBarState();
}

class _AudioPlayerBarState extends State<AudioPlayerBar> {
  final AudioPlayer _player = AudioPlayer();

  bool _playing = false;
  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;
  double _volume = 1.0;
  double _rate = 1.0;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;
  StreamSubscription<PlayerState>? _stateSub;

  @override
  void initState() {
    super.initState();
    _dur = Duration(milliseconds: (widget.totalSec * 1000).round());
    _setup();
    widget.seekRequest?.addListener(_onSeekRequest);
  }

  void _onSeekRequest() {
    final sec = widget.seekRequest?.value;
    if (sec == null) return;
    widget.seekRequest!.value = null;
    _seekTo(Duration(milliseconds: (sec * 1000).round()));
  }

  /// 跳转到指定位置；若当前未在播放则从该处开始播放。
  Future<void> _seekTo(Duration target) async {
    final total = _dur.inMilliseconds > 0
        ? _dur
        : Duration(milliseconds: (widget.totalSec * 1000).round());
    final clamped = total.inMilliseconds > 0 && target > total ? total : target;
    try {
      await _player.seek(clamped);
      if (!mounted) return;
      setState(() => _pos = clamped);
      if (!_playing) {
        await _player.setPlaybackRate(_rate);
        await _player.play(DeviceFileSource(widget.filePath));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('音频跳转失败：$e')));
      }
    }
  }

  Future<void> _setup() async {
    _posSub = _player.onPositionChanged.listen((d) {
      if (mounted) setState(() => _pos = d);
    });
    _durSub = _player.onDurationChanged.listen((d) {
      if (mounted && d > Duration.zero) setState(() => _dur = d);
    });
    _stateSub = _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _playing = s == PlayerState.playing);
    });
    try {
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.play(DeviceFileSource(widget.filePath));
      await _player.pause();
    } catch (_) {
      // 文件缺失或格式不支持时静默，用户点播放时再提示
    }
  }

  @override
  void didUpdateWidget(covariant AudioPlayerBar old) {
    super.didUpdateWidget(old);
    if (old.seekRequest != widget.seekRequest) {
      old.seekRequest?.removeListener(_onSeekRequest);
      widget.seekRequest?.addListener(_onSeekRequest);
    }
    if (old.filePath != widget.filePath) {
      _pos = Duration.zero;
      _playing = false;
      _setup();
    }
  }

  @override
  void dispose() {
    widget.seekRequest?.removeListener(_onSeekRequest);
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    try {
      if (_playing) {
        await _player.pause();
      } else {
        if (_pos >= _dur && _dur > Duration.zero) {
          await _player.seek(Duration.zero);
        }
        await _player.setPlaybackRate(_rate);
        await _player.play(DeviceFileSource(widget.filePath));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('音频播放失败：$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _dur.inMilliseconds > 0
        ? _dur
        : Duration(milliseconds: (widget.totalSec * 1000).round());
    final posClamped = _pos.inMilliseconds > total.inMilliseconds
        ? total
        : _pos;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      decoration: BoxDecoration(
        color: AppColors.cardWarm,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          _RoundIconBtn(
            icon: _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            onPressed: _toggle,
          ),
          const SizedBox(width: 10),
          Text(
            '${formatDuration(posClamped.inMilliseconds / 1000)} / '
            '${formatDuration(total.inMilliseconds / 1000)}',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3.5,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                activeTrackColor: AppColors.primary,
                inactiveTrackColor: AppColors.primarySoft,
                thumbColor: AppColors.primary,
              ),
              child: Slider(
                value: total.inMilliseconds == 0
                    ? 0
                    : posClamped.inMilliseconds / total.inMilliseconds,
                onChanged: (v) async {
                  final target = Duration(
                    milliseconds: (v * total.inMilliseconds).round(),
                  );
                  setState(() => _pos = target);
                  await _player.seek(target);
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            _volume == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
            size: 18,
            color: AppColors.primary,
          ),
          SizedBox(
            width: 72,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
                activeTrackColor: AppColors.primary,
                inactiveTrackColor: AppColors.primarySoft,
                thumbColor: AppColors.primary,
              ),
              child: Slider(
                value: _volume,
                onChanged: (v) {
                  setState(() => _volume = v);
                  _player.setVolume(v);
                },
              ),
            ),
          ),
          const SizedBox(width: 6),
          PopupMenuButton<double>(
            initialValue: _rate,
            onSelected: (r) {
              setState(() => _rate = r);
              _player.setPlaybackRate(r);
            },
            itemBuilder: (_) => [
              for (final r in const [0.75, 1.0, 1.25, 1.5, 2.0])
                PopupMenuItem(value: r, child: Text('${r}x')),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${_rate}x',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundIconBtn extends StatelessWidget {
  const _RoundIconBtn({required this.icon, this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(icon, size: 22, color: Colors.white),
        ),
      ),
    );
  }
}

/// 复制文本到剪贴板并提示。
void copyText(BuildContext context, String text) {
  Clipboard.setData(ClipboardData(text: text));
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('已复制到剪贴板'), duration: Duration(seconds: 1)),
  );
}

/// 导出音频文件（保存对话框，按原始格式保存）。
Future<void> exportAudio(
  BuildContext context,
  String defaultName,
  String sourcePath,
) async {
  final ext = sourcePath.contains('.')
      ? sourcePath.split('.').last.toLowerCase()
      : 'wav';
  final Uint8List bytes;
  try {
    bytes = await File(sourcePath).readAsBytes();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('读取音频文件失败：$e')));
    }
    return;
  }
  final uri = await FilePicker.saveFile(
    dialogTitle: '导出音频',
    fileName: '$defaultName.$ext',
    bytes: bytes,
  );
  if (uri == null || context.mounted == false) return;
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text('已导出到 ${uri.toFilePath()}')));
}

/// 导出为 DOCX（保存对话框）。
Future<void> exportDocx(
  BuildContext context,
  String defaultName,
  List<TranscriptSegment> segments, {
  DateTime? createdAt,
  double? durationSec,
}) async {
  final bytes = DocxExporter.build(
    title: defaultName,
    segments: segments,
    createdAt: createdAt,
    durationSec: durationSec,
  );
  final uri = await FilePicker.saveFile(
    dialogTitle: '导出转写文档',
    fileName: '$defaultName.docx',
    mimeType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    bytes: bytes,
  );
  if (uri == null || context.mounted == false) return;
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text('已导出到 $uri')));
}
