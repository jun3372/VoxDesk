import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../data/transcript_models.dart';
import '../services/audio_decode_service.dart';
import '../services/diarization_engine.dart';
import '../services/history_service.dart';
import '../services/transcribe_pipeline.dart';
import '../services/vad_engine.dart';
import 'model_controller.dart';

/// 上传音频转写的状态机：空 → 已选文件 → 转写中 → 完成。
enum UploadPhase { idle, fileSelected, transcribing, done }

class UploadController extends ChangeNotifier {
  UploadController({required this.models, required this.history});

  final ModelController models;
  final HistoryService history;

  final VadEngine _vad = VadEngine();

  UploadPhase phase = UploadPhase.idle;

  // 文件信息
  String? filePath;
  String? fileName;
  int? fileSizeBytes;
  double durationSec = 0;
  List<double> peaks = [];

  /// 解码/读取文件中。
  bool preparingFile = false;

  // 转写选项与进度
  bool usePunctuation = true;

  /// 是否启用说话人自动标注（关闭后转写结果不带说话人标签）。
  bool useDiarization = false;
  bool paused = false;
  bool _cancelRequested = false;
  double progress = 0;
  String stageLabel = '';
  int elapsedSec = 0;
  int etaSec = 0;
  String? error;

  List<TranscriptSegment> segments = [];
  String? viewedHistoryId;

  /// 转写历史写入完成后的回调（参数为记录 id，用于刷新并激活侧边栏历史列表）。
  void Function(String historyId)? onHistorySaved;

  /// 点击转写时间戳后的播放跳转请求（秒）；由音频播放条消费后置回 null。
  final ValueNotifier<double?> seekRequest = ValueNotifier<double?>(null);

  Timer? _ticker;

  bool get transcribing => phase == UploadPhase.transcribing;
  bool get hasFile => filePath != null;
  bool get canStart =>
      hasFile && models.ready && !preparingFile && !transcribing;

  int get charCount =>
      segments.fold(0, (n, s) => n + s.text.replaceAll(' ', '').length);

  bool get punctuationEnabled => usePunctuation && models.punctuationAvailable;

  Future<void> pickFile() async {
    try {
      final file = await FilePicker.pickFile(dialogTitle: '选择音频文件');
      final path = file?.path;
      if (path != null && path.isNotEmpty) await setFile(path);
    } catch (e) {
      error = '选择文件失败：$e';
      debugPrint('选择音频文件失败: $e');
      notifyListeners();
    }
  }

  Future<void> setFile(String path) async {
    if (transcribing) return;
    if (!AudioDecodeService.isSupported(path)) {
      error = '不支持的音频格式，请选择 WAV / MP3 / M4A / FLAC / OGG 文件';
      notifyListeners();
      return;
    }
    error = null;
    viewedHistoryId = null;
    preparingFile = true;
    filePath = path;
    fileName = path.split(Platform.pathSeparator).last;
    segments = [];
    phase = UploadPhase.fileSelected;
    notifyListeners();

    try {
      fileSizeBytes = File(path).lengthSync();
      final decoded = await AudioDecodeService.decodeToMono16k(path);
      _decoded = decoded.samples;
      durationSec = decoded.durationSec;
      peaks = AudioDecodeService.waveformFromSamples(decoded.samples);
    } catch (e) {
      debugPrint('音频解码失败: $e');
      // 先重置文件状态，再保留错误信息展示，避免界面静默回到空状态
      _resetFile();
      error = '音频解码失败：$e';
    } finally {
      preparingFile = false;
      notifyListeners();
    }
  }

  Float32List? _decoded;

  void clearFile() {
    if (transcribing) return;
    _resetFile();
    notifyListeners();
  }

  void _resetFile() {
    filePath = null;
    fileName = null;
    fileSizeBytes = null;
    durationSec = 0;
    peaks = [];
    segments = [];
    _decoded = null;
    viewedHistoryId = null;
    progress = 0;
    elapsedSec = 0;
    etaSec = 0;
    error = null;
    if (phase != UploadPhase.idle) phase = UploadPhase.idle;
  }

  /// 「重新上传」：回到空状态。
  void resetToIdle() {
    if (transcribing) return;
    _resetFile();
    notifyListeners();
  }

  /// 「重新转写」：把当前文件重新识别一遍。
  /// 回看历史进入的完成态没有缓存解码样本，需先重新解码。
  Future<void> retranscribe() async {
    if (transcribing || !hasFile) return;
    if (_decoded == null) {
      error = null;
      preparingFile = true;
      notifyListeners();
      try {
        final decoded = await AudioDecodeService.decodeToMono16k(filePath!);
        _decoded = decoded.samples;
        durationSec = decoded.durationSec;
        peaks = AudioDecodeService.waveformFromSamples(decoded.samples);
      } catch (e) {
        debugPrint('音频解码失败: $e');
        error = '音频解码失败：$e';
        return;
      } finally {
        preparingFile = false;
        notifyListeners();
      }
    }
    await startTranscription();
  }

  /// 「清空」：只清空转写结果，保留已选文件。
  void clearResult() {
    if (transcribing) return;
    segments = [];
    viewedHistoryId = null;
    progress = 0;
    if (phase == UploadPhase.done) {
      phase = hasFile ? UploadPhase.fileSelected : UploadPhase.idle;
      if (!hasFile) _resetFile();
    }
    notifyListeners();
  }

  void setUsePunctuation(bool v) {
    usePunctuation = v;
    notifyListeners();
  }

  void setUseDiarization(bool v) {
    useDiarization = v;
    notifyListeners();
  }

  /// 开始转写：VAD 分段 → 并发逐句识别（流式回显）→ 说话人分离 → 保存历史。
  ///
  /// 分离模型在识别期间并行预加载，但分离重计算与识别串行（识别完成后再
  /// 跑）：实测两者并行会因内存带宽互踩——分离跑多久、识别结果就停多久，
  /// 总耗时反而比串行长。文本先流式回显、分离完成后统一回填说话人标签。
  Future<void> startTranscription() async {
    if (!canStart || _decoded == null) return;
    final samples = _decoded!;
    final p = models.paths!;

    phase = UploadPhase.transcribing;
    segments = [];
    progress = 0;
    elapsedSec = 0;
    etaSec = 0;
    paused = false;
    _cancelRequested = false;
    stageLabel = '语音识别中';
    error = null;
    _startTicker();
    notifyListeners();

    final sw = Stopwatch()..start();
    // 说话人标注开关在转写开始时快照，转写过程中不响应选项变化
    final diarize = useDiarization;
    // 未启动时为 null；已启动时元素为 null 表示分离失败（等同无标签）
    Future<List<DiarSegment>?>? diarFuture;
    // 识别流水线是否已结束；结束后分离进度才接管进度条（0.9 → 1.0）
    var feedDone = false;
    // 分离结果已就绪（分离常早于识别结束）；此后已识别段落立即打标，
    // 新识别段落也即时回填，实现「边转写边显示说话人」
    List<({double start, double end, int speaker})>? settledDiar;

    void applySpeakers() {
      if (settledDiar == null || segments.isEmpty) return;
      segments = assignSpeakers(segments: segments, diarSegments: settledDiar!);
    }

    Future<List<DiarSegment>?> launchDiarization() {
      if (diarFuture != null || !diarize || !p.diarizationReady) {
        return diarFuture ?? Future.value(null);
      }
      final future = () async {
        final ok = await models.ensureDiarization();
        if (!ok || _cancelRequested) return <DiarSegment>[];
        return models.diarization.process(
          samples,
          onProgress: (done, total) {
            if (!feedDone || _cancelRequested) return;
            final ratio = done / (total == 0 ? 1 : total);
            progress = 0.9 + ratio * 0.1;
            _updateEta(sw, progress, 1.0);
            notifyListeners();
          },
        );
      }();
      // 分离失败不应中断转写，等同无标签
      final wrapped = future
          .catchError((Object e) {
            debugPrint('说话人分离失败: $e');
            return <DiarSegment>[];
          })
          .then((segs) {
            if (segs.isNotEmpty && !_cancelRequested) {
              settledDiar = [
                for (final d in segs)
                  (start: d.start, end: d.end, speaker: d.speaker),
              ];
              applySpeakers();
              notifyListeners();
            }
            return segs;
          });
      diarFuture = wrapped;
      return wrapped;
    }

    try {
      _vad.load(p.sileroVad);
      // 分离模型与识别并行预加载（仅加载、几乎不占算力）；分离重计算
      // 必须与识别串行——实测两者并行会因内存带宽互踩，分离跑多久识别
      // 就停多久（6.4 分钟音频的结果输出空窗达 77-133s），串行的总耗时
      // 反而更短、结果输出平滑
      if (diarize && p.diarizationReady) {
        unawaited(models.ensureDiarization());
      }
      await streamTranscribe(
        samples: samples,
        vad: _vad,
        recognize: (speech) =>
            models.asr.recognize(speech, punctuate: punctuationEnabled),
        isCancelled: () => _cancelRequested,
        isPaused: () => paused,
        maxInFlight: models.asr.workerCount * 2,
        onSegment: (seg) {
          _insertSegmentSorted(seg);
          applySpeakers();
        },
        onProgress: (ratio) {
          progress = ratio * 0.9;
          _updateEta(sw, ratio, 0.9);
        },
        onChanged: notifyListeners,
      );
      feedDone = true;

      // —— 识别完成后再跑说话人分离（与识别串行，见前述说明）——
      final diarUsable =
          diarize && p.diarizationReady && samples.length > 16000 * 3;
      List<DiarSegment>? diarSegs;
      if (diarUsable && !_cancelRequested) {
        stageLabel = '说话人分离中';
        notifyListeners();
        diarSegs = await launchDiarization();
      } else if (diarUsable) {
        models.diarization.cancel();
      }
      if (!_cancelRequested && diarSegs != null && diarSegs.isNotEmpty) {
        applySpeakers();
      }

      progress = 1;
      stageLabel = '';

      // —— 保存历史 ——
      if (segments.isNotEmpty) {
        // 重新转写：更新原记录，不新增条目；原记录已删除时回退为新增。
        final updated =
            viewedHistoryId != null &&
            await history.updateSegments(viewedHistoryId!, segments);
        if (!updated) {
          final item = await history.saveFileResult(
            title: fileName ?? '未命名音频',
            sourcePath: filePath!,
            durationSec: durationSec,
            segments: segments,
            fileSizeBytes: fileSizeBytes,
          );
          viewedHistoryId = item.id;
        }
        onHistorySaved?.call(viewedHistoryId!);
      }
      phase = UploadPhase.done;
    } catch (e) {
      error = '转写失败：$e';
      phase = UploadPhase.fileSelected;
    } finally {
      _ticker?.cancel();
      _vad.free();
      paused = false;
      notifyListeners();
    }
  }

  /// 识别按段落派发、完成顺序乱序返回，按起点时间排序插入保持段落有序。
  /// 派发顺序本身是时间升序，倒序扫描通常一次即命中。
  void _insertSegmentSorted(TranscriptSegment seg) {
    var i = segments.length;
    while (i > 0 && segments[i - 1].startSec > seg.startSec) {
      i--;
    }
    segments.insert(i, seg);
  }

  void pause() {
    if (!transcribing) return;
    paused = true;
    notifyListeners();
  }

  void resume() {
    paused = false;
    notifyListeners();
  }

  /// 「结束」：停止转写，保留已生成的部分结果。
  void finish() {
    if (!transcribing) return;
    _cancelRequested = true;
    // 分离与识别并行时，同步请求引擎中止当前计算
    models.diarization.cancel();
    paused = false;
    notifyListeners();
  }

  /// 重命名说话人：应用到全文该说话人的所有段落；
  /// 已对应历史记录时同步持久化。名称留空 = 恢复默认标签。
  Future<void> renameSpeaker(int speaker, String name) async {
    final custom = name.trim();
    var changed = false;
    for (final s in segments) {
      if (s.speaker != speaker) continue;
      final newName = custom.isEmpty ? null : custom;
      if (s.speakerName == newName) continue;
      s.speakerName = newName;
      changed = true;
    }
    if (!changed) return;
    notifyListeners();
    final id = viewedHistoryId;
    if (id != null) await history.updateSegments(id, segments);
  }

  /// 回看历史记录（文件转写）。正文立即渲染，波形后台补算，
  /// 避免解码整个音频阻塞首帧。
  Future<void> viewHistory(
    HistoryItem item,
    List<TranscriptSegment> segs,
  ) async {
    if (transcribing) return;
    phase = UploadPhase.done;
    fileName = item.title;
    filePath = item.sourcePath;
    fileSizeBytes = item.fileSizeBytes;
    durationSec = item.durationSec;
    segments = segs;
    viewedHistoryId = item.id;
    peaks = [];
    error = null;
    progress = 1;
    _decoded = null;
    notifyListeners();

    final path = filePath;
    if (path != null && File(path).existsSync()) {
      final peaks = await AudioDecodeService.computeWaveform(path);
      // 等待期间用户可能已切换到其他记录，旧波形不覆盖新内容
      if (filePath == path) {
        this.peaks = peaks;
        notifyListeners();
      }
    }
  }

  // —— 内部 ——

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!transcribing) return t.cancel();
      if (paused) return;
      elapsedSec++;
      notifyListeners();
    });
  }

  void _updateEta(Stopwatch sw, double ratio, double phaseWeight) {
    if (ratio > 0.02) {
      final total = sw.elapsed.inSeconds / ratio;
      etaSec = (total - sw.elapsed.inSeconds).round().clamp(0, 24 * 3600);
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _vad.free();
    seekRequest.dispose();
    super.dispose();
  }
}
