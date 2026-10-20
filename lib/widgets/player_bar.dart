import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart' as file_selector;
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

/// macOS 原生保存面板（MainFlutterWindow.swift 内 SavePanelPlugin）：
/// file_picker 的 NSSavePanel 固定隐藏扩展名，对话框里默认文件名看不到
/// 后缀；Windows/Linux 的 file_picker 无此问题，维持原实现。
const MethodChannel _macSavePanel = MethodChannel('voxdesk/save_panel');

/// 弹出保存对话框，返回所选目标路径（用户取消返回 null）；不写入内容，
/// 由调用方自行落盘。
Future<Uri?> _saveFileDialog(
  BuildContext context, {
  required String fileName,
  String? dialogTitle,
}) async {
  if (Platform.isMacOS) {
    final path = await _macSavePanel.invokeMethod<String>('save', {
      'fileName': fileName,
      'dialogTitle': dialogTitle,
    });
    return path == null || path.isEmpty ? null : Uri.file(path);
  }
  if (Platform.isLinux) {
    // file_picker 的 Linux 实现直连 xdg-desktop-portal（D-Bus），离网或未装
    // portal 的系统直接抛 ServiceUnknown、导出全部失败；改用 GTK 原生对话框
    // （file_selector_linux）：GtkFileChooserNative 只在沙箱环境才走 portal，
    // 普通桌面直接弹本地对话框，不依赖任何系统服务
    final location = await file_selector.getSaveLocation(
      suggestedName: fileName,
      confirmButtonText: '导出',
    );
    if (location == null) return null;
    final path = location.path;
    // GTK 该对话框默认不做覆盖确认，避免静默覆盖已有文件
    if (File(path).existsSync()) {
      final overwrite = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            '文件已存在',
            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
          ),
          contentPadding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
          content: Text('「$fileName」已存在，确定覆盖吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('覆盖', style: TextStyle(color: AppColors.primary)),
            ),
          ],
        ),
      );
      if (overwrite != true) return null;
    }
    return Uri.file(path);
  }
  return FilePicker.saveFile(
    dialogTitle: dialogTitle,
    fileName: fileName,
    bytes: Uint8List(0),
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
  Uri? uri;
  try {
    // 先取目标路径、再流式拷贝：saveFile(bytes) 要求整份内容驻留内存，
    // 长会话录音可达数百 MB，与识别引擎并存时易失败
    uri = await _saveFileDialog(
      context,
      fileName: '$defaultName.$ext',
      dialogTitle: '导出音频',
    );
    if (uri != null) await File(sourcePath).copy(uri.toFilePath());
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('导出音频失败：$e')));
    }
    return;
  }
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
  Uri? uri;
  try {
    final bytes = DocxExporter.build(
      title: defaultName,
      segments: segments,
      createdAt: createdAt,
      durationSec: durationSec,
    );
    uri = await _saveFileDialog(
      context,
      fileName: '$defaultName.docx',
      dialogTitle: '导出转写文档',
    );
    if (uri != null) {
      await File(uri.toFilePath()).writeAsBytes(bytes, flush: true);
    }
  } catch (e) {
    // 目标文件被占用（如已在 Word 中打开同名文件）、权限不足等插件
    // 内部异常若不上浮提示，表现为「点击导出无任何反应」
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('导出文档失败：$e')));
    }
    return;
  }
  if (uri == null || context.mounted == false) return;
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text('已导出到 ${uri.toFilePath()}')));
}
