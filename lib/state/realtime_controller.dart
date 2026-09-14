import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/transcript_models.dart';
import '../services/audio_decode_service.dart';
import '../services/diarization_engine.dart';
import '../services/history_service.dart';
import '../services/recorder_service.dart';
import '../services/vad_engine.dart';
import '../services/wav_io.dart';
import 'model_controller.dart';

/// 实时转写状态机：就绪 → 录音中 → 已结束。
enum RealtimePhase { idle, recording, ended }

class RealtimeController extends ChangeNotifier {
  RealtimeController({required this.models, required this.history});

  final ModelController models;
  final HistoryService history;

  final RecorderService _recorder = RecorderService();
  final VadEngine _vad = VadEngine();
  VadWindowFeeder? _feeder;

  RealtimePhase phase = RealtimePhase.idle;
  bool paused = false;
  bool saving = false;
  bool diarizing = false;
  String? error;

  /// 是否启用说话人自动标注（关闭后转写结果不带说话人标签）。
  bool useDiarization = false;

  /// 是否启用数字与标点规范化（依赖本地标点恢复模型）。
  bool usePunctuation = true;

  int elapsedSec = 0;
  DateTime? startedAt;
  String deviceName = '系统默认麦克风';

  List<TranscriptSegment> segments = [];

  /// 是否有语音段正在识别中（界面显示高亮占位行）。
  bool recognizing = false;

  /// 录音中增量说话人分离进行中（界面显示「说话人标注中」标签）。
  bool liveDiarizing = false;

  /// 录音中的实时波形幅度（最新若干根柱）。
  final List<double> liveWave = List.filled(48, 0, growable: true);

  String? viewedHistoryId;
  double endedDurationSec = 0;

  /// 已结束会话的录音文件（session.wav）路径；null 表示保存失败或旧记录无录音。
  String? audioPath;
  int? audioSizeBytes;

  /// 已结束会话的波形峰位（回放页展示，与上传页一致）。
  List<double> peaks = [];

  // —— 重新转写 ——
  bool retranscribing = false;
  bool retranscribePaused = false;
  double retranscribeProgress = 0;
  String stageLabel = '';
  int retranscribeElapsedSec = 0;
  int retranscribeEtaSec = 0;
  bool _retranscribeCancel = false;
  Timer? _retranscribeTicker;

  bool get recording => phase == RealtimePhase.recording;
  bool get canStart =>
      models.ready && phase != RealtimePhase.recording && !retranscribing;

  /// 是否可以重新转写（需要已保存的录音文件且模型就绪；
  /// 说话人标注期间草稿尚未转正，不允许重新转写）。
  bool get canRetranscribe =>
      phase == RealtimePhase.ended &&
      !retranscribing &&
      !diarizing &&
      audioPath != null &&
      models.ready;

  int get charCount =>
      segments.fold(0, (n, s) => n + s.text.replaceAll(' ', '').length);

  /// 与上传页一致：开关打开且检测到标点模型时才启用标点恢复。
  bool get punctuationEnabled => usePunctuation && models.punctuationAvailable;

  /// 会话历史写入完成后的回调（参数为记录 id，用于刷新并激活侧边栏历史列表）。
  void Function(String historyId)? onHistorySaved;

  /// 点击转写时间戳后的播放跳转请求（秒）；由音频播放条消费后置回 null。
  final ValueNotifier<double?> seekRequest = ValueNotifier<double?>(null);

  Timer? _ticker;
  final List<Float32List> _chunks = [];
  int _totalSamples = 0;
  Future<void> _queue = Future.value();
  bool _stopping = false;

  // —— 录音中增量说话人分离 ——
  // 分离引擎一次只能跑一个任务且整轮计算较重，用间隔节流 +
  // 「上一轮未结束则跳过」的自然背控制 CPU 占用。
  static const int _incrDiarIntervalSec = 45;
  int _sessionGen = 0;
  bool _incrDiarBusy = false;
  double _incrDiarMarkSec = 0;

  /// 说话人标注开关在会话开始时快照，会话内不响应选项变化。
  bool _sessionDiarize = false;

  void setUseDiarization(bool v) {
    useDiarization = v;
    notifyListeners();
  }

  void setUsePunctuation(bool v) {
    usePunctuation = v;
    notifyListeners();
  }

  Future<void> start() async {
    if (!canStart) {
      error = models.ready ? null : '请先在侧边栏加载模型';
      notifyListeners();
      return;
    }
    error = null;
    viewedHistoryId = null;
    audioPath = null;
    audioSizeBytes = null;
    peaks = [];
    _sessionGen++;
    _incrDiarBusy = false;
    _incrDiarMarkSec = 0;
    liveDiarizing = false;
    _sessionDiarize = useDiarization;
    try {
      _vad.load(models.paths!.sileroVad);
      _feeder = VadWindowFeeder(_onWindow);
      await _recorder.start(_onSamples);
    } catch (e) {
      error = '$e';
      notifyListeners();
      return;
    }

    startedAt = DateTime.now();
    elapsedSec = 0;
    paused = false;
    _stopping = false;
    segments = [];
    _chunks.clear();
    _totalSamples = 0;
    phase = RealtimePhase.recording;
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (phase != RealtimePhase.recording || paused) return;
      elapsedSec++;
      notifyListeners();
    });
    notifyListeners();
  }

  void pause() {
    if (!recording) return;
    paused = true;
    notifyListeners();
  }

  void resume() {
    paused = false;
    notifyListeners();
  }

  /// 结束录音：冲出剩余语音段，落盘录音草稿后立即写入历史——
  /// 记录即刻出现在左侧历史列表；说话人标注在后台进行，完成后
  /// 原地更新该记录的说话人标签，不阻塞历史可见性。
  Future<void> stop() async {
    if (!recording || _stopping) return;
    _stopping = true;
    _ticker?.cancel();
    saving = true;
    notifyListeners();

    try {
      await _recorder.stop();
      _vad.flush();
      // 冲出残余语音段
      while (_vad.hasSegment) {
        final s = _vad.front();
        _enqueue(s.samples, s.start);
        _vad.pop();
      }
      await _queue;
      _vad.free();

      endedDurationSec = _totalSamples / VadEngine.sampleRate;
      final fullAudio = _mergeChunks();
      peaks = AudioDecodeService.waveformFromSamples(fullAudio);

      // 两段式保存：先落盘录音文件（供结束页立即回放），随即立即写入
      // 历史记录；说话人标注后台补齐后原地更新，历史列表先见为快。
      final draft = await history.createRealtimeSessionDraft(
        createdAt: startedAt ?? DateTime.now(),
        durationSec: endedDurationSec,
        device: deviceName,
        audio: fullAudio,
      );
      viewedHistoryId = draft.id;
      audioPath = draft.audioPath;
      if (audioPath != null) {
        try {
          audioSizeBytes = File(audioPath!).lengthSync();
        } catch (_) {}
      }
      try {
        await history.finalizeRealtimeSession(draft, segments);
        onHistorySaved?.call(draft.id);
      } catch (e) {
        error = '保存历史记录失败：$e';
      }
      phase = RealtimePhase.ended;
      saving = false;
      notifyListeners();

      // —— 后台说话人分离 ——
      final baseSegments = List<TranscriptSegment>.of(segments);
      var finalSegments = baseSegments;
      if (_sessionDiarize &&
          models.diarizationAvailable &&
          fullAudio.length > 16000 * 3) {
        diarizing = true;
        notifyListeners();
        try {
          final ok = await models.ensureDiarization();
          if (ok) {
            final diarSegs = await models.diarization.process(fullAudio);
            finalSegments = assignSpeakers(
              segments: baseSegments,
              diarSegments: [
                for (final d in diarSegs)
                  (start: d.start, end: d.end, speaker: d.speaker),
              ],
            );
            // 用户未离开当前会话时同步刷新界面（分离期间可能已切换
            // 到其他历史记录或重新转写，此时不能覆盖新内容）
            if (viewedHistoryId == draft.id &&
                phase == RealtimePhase.ended &&
                !retranscribing) {
              segments = finalSegments;
            }
            // 标注结果原地更新历史记录（条目已在列表中，不新增）
            await history.updateSegments(draft.id, finalSegments);
          }
        } catch (e) {
          debugPrint('说话人标注失败: $e');
        }
        diarizing = false;
        notifyListeners();
      }
    } catch (e) {
      error = '保存会话失败：$e';
      phase = RealtimePhase.ended;
      saving = false;
      diarizing = false;
      notifyListeners();
    }
  }

  /// 「重新开始实时转写」。
  Future<void> restart() async {
    if (recording || retranscribing) return;
    segments = [];
    elapsedSec = 0;
    endedDurationSec = 0;
    diarizing = false;
    saving = false;
    liveDiarizing = false;
    viewedHistoryId = null;
    audioPath = null;
    audioSizeBytes = null;
    peaks = [];
    _resetRetranscribe();
    error = null;
    startedAt = null;
    phase = RealtimePhase.idle;
    notifyListeners();
  }

  /// 重命名说话人：应用到全文该说话人的所有段落；
  /// 会话已转正为历史记录时同步持久化。名称留空 = 恢复默认标签。
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
    // 录音中的会话尚未写入历史，名称会随结束时的 finalize 一并保存
    if (phase == RealtimePhase.ended && !retranscribing && id != null) {
      await history.updateSegments(id, segments);
    }
  }

  /// 回看实时会话历史。
  Future<void> viewHistory(
    HistoryItem item,
    List<TranscriptSegment> segs,
  ) async {
    if (recording || retranscribing) return;
    phase = RealtimePhase.ended;
    segments = segs;
    viewedHistoryId = item.id;
    startedAt = item.createdAt;
    endedDurationSec = item.durationSec;
    elapsedSec = item.durationSec.round();
    deviceName = item.device ?? '系统默认麦克风';
    diarizing = false;
    saving = false;
    error = null;
    audioPath = null;
    audioSizeBytes = item.fileSizeBytes;
    peaks = [];
    notifyListeners();

    // 录音文件与波形后台补算，不阻塞历史列表点击的首帧
    final path = await history.sessionAudioPath(item);
    if (viewedHistoryId != item.id) return;
    audioPath = path;
    if (path != null) {
      try {
        audioSizeBytes = File(path).lengthSync();
      } catch (_) {}
      final wave = await AudioDecodeService.computeWaveform(path);
      // 等待期间用户可能已切换到其他记录，旧波形不覆盖新内容
      if (viewedHistoryId == item.id && phase == RealtimePhase.ended) {
        peaks = wave;
        notifyListeners();
      }
    } else {
      notifyListeners();
    }
  }

  // —— 重新转写 ——

  /// 「重新转写」：读取已保存的录音文件，重新执行 VAD 分段 → 逐句识别 →
  /// 说话人分离，完成后更新原历史记录。
  Future<void> retranscribe() async {
    if (!canRetranscribe) return;
    final path = audioPath!;

    Float32List samples;
    try {
      final wav = parseWav(await File(path).readAsBytes());
      samples = toMono16k(wav.samples, wav.sampleRate, wav.channels);
    } catch (e) {
      error = '读取录音文件失败：$e';
      notifyListeners();
      return;
    }

    _retranscribeCancel = false;
    retranscribePaused = false;
    retranscribing = true;
    retranscribeProgress = 0;
    retranscribeElapsedSec = 0;
    retranscribeEtaSec = 0;
    stageLabel = '语音识别中';
    error = null;
    segments = [];
    diarizing = false;
    _startRetranscribeTicker();
    notifyListeners();

    final sw = Stopwatch()..start();
    // 与上传转写一致：分离在检测到首段语音后与逐句识别并行
    // 说话人标注开关在开始时快照
    final diarize = useDiarization;
    Future<List<DiarSegment>?>? diarFuture;
    var feedDone = false;
    // 分离结果已就绪；此后已识别段落立即打标、新段落即时回填
    List<({double start, double end, int speaker})>? settledDiar;

    void applySpeakers() {
      if (settledDiar == null || segments.isEmpty) return;
      segments = assignSpeakers(segments: segments, diarSegments: settledDiar!);
    }

    Future<List<DiarSegment>?> launchDiarization() {
      final available =
          diarize &&
          models.diarizationAvailable &&
          samples.length > VadEngine.sampleRate * 3;
      if (diarFuture != null || !available) {
        return diarFuture ?? Future.value(null);
      }
      final future = () async {
        final ok = await models.ensureDiarization();
        if (!ok || _retranscribeCancel) return <DiarSegment>[];
        return models.diarization.process(
          samples,
          onProgress: (done, total) {
            if (!feedDone || _retranscribeCancel) return;
            final ratio = done / (total == 0 ? 1 : total);
            retranscribeProgress = 0.9 + ratio * 0.1;
            _updateRetranscribeEta(sw, retranscribeProgress);
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
            if (segs.isNotEmpty && !_retranscribeCancel) {
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
      _vad.load(models.paths!.sileroVad);
      await _retranscribeStream(
        samples,
        sw,
        onFirstSpeech: launchDiarization,
        onSegmentAdded: applySpeakers,
      );
      feedDone = true;

      // —— 与识别并行的说话人分离收尾 ——
      List<DiarSegment>? diarSegs;
      if (diarFuture != null) {
        if (_retranscribeCancel) {
          models.diarization.cancel();
        } else {
          stageLabel = '说话人分离中';
          notifyListeners();
          diarSegs = await diarFuture!;
        }
      }
      // 分离完成时通常已即时回填；此处兜底（如最后一批段落晚于分离完成）
      if (!_retranscribeCancel && diarSegs != null && diarSegs.isNotEmpty) {
        applySpeakers();
      }

      retranscribeProgress = 1;
      stageLabel = '';

      // 更新原历史记录；记录已被删除时回退为新增（带上录音）。
      final updated =
          viewedHistoryId != null &&
          await history.updateSegments(viewedHistoryId!, segments);
      if (!updated) {
        final fallbackDraft = await history.createRealtimeSessionDraft(
          createdAt: startedAt ?? DateTime.now(),
          durationSec: endedDurationSec,
          device: deviceName,
          audio: samples,
        );
        final item = await history.finalizeRealtimeSession(
          fallbackDraft,
          segments,
        );
        viewedHistoryId = item.id;
        audioPath = fallbackDraft.audioPath;
      }
      onHistorySaved?.call(viewedHistoryId!);
    } catch (e) {
      error = '重新转写失败：$e';
    } finally {
      _retranscribeTicker?.cancel();
      _vad.free();
      retranscribing = false;
      retranscribePaused = false;
      notifyListeners();
    }
  }

  void pauseRetranscribe() {
    if (!retranscribing) return;
    retranscribePaused = true;
    notifyListeners();
  }

  void resumeRetranscribe() {
    retranscribePaused = false;
    notifyListeners();
  }

  /// 「结束」：停止重新转写，保留已生成的部分结果。
  void finishRetranscribe() {
    if (!retranscribing) return;
    _retranscribeCancel = true;
    // 分离与识别并行时，同步请求引擎中止当前计算
    models.diarization.cancel();
    retranscribePaused = false;
    notifyListeners();
  }

  void _resetRetranscribe() {
    _retranscribeTicker?.cancel();
    retranscribing = false;
    retranscribePaused = false;
    retranscribeProgress = 0;
    retranscribeElapsedSec = 0;
    retranscribeEtaSec = 0;
    stageLabel = '';
    _retranscribeCancel = false;
  }

  /// 与上传页一致的分段识别：按窗口粒度喂入 VAD，每产出一个语音段立即识别。
  /// [onFirstSpeech] 在检测到首个语音段时触发（用于并行启动说话人分离）；
  /// [onSegmentAdded] 在每个段落写入结果后触发（用于即时回填说话人标签）。
  Future<void> _retranscribeStream(
    Float32List samples,
    Stopwatch sw, {
    void Function()? onFirstSpeech,
    void Function()? onSegmentAdded,
  }) async {
    const windowSize = 512;
    const windowsPerYield = 32; // 约 1 秒让出一次事件循环
    var fedSamples = 0;
    var windows = 0;

    Future<void> drainAndRecognize() async {
      while (_vad.hasSegment) {
        final s = _vad.front();
        _vad.pop();
        if (_retranscribeCancel) continue;
        onFirstSpeech?.call();
        while (retranscribePaused && !_retranscribeCancel) {
          await Future<void>.delayed(const Duration(milliseconds: 120));
        }
        if (_retranscribeCancel) continue;
        String text;
        try {
          text = await models.asr.recognize(
            s.samples,
            punctuate: punctuationEnabled,
          );
        } catch (e) {
          text = '';
          debugPrint('重新转写识别失败: $e');
        }
        if (text.isNotEmpty) {
          segments.add(
            TranscriptSegment(
              startSec: s.start / VadEngine.sampleRate,
              endSec: (s.start + s.samples.length) / VadEngine.sampleRate,
              text: text,
            ),
          );
          onSegmentAdded?.call();
        }
        notifyListeners();
      }
    }

    while (fedSamples < samples.length && !_retranscribeCancel) {
      final end = (fedSamples + windowSize).clamp(0, samples.length);
      _vad.acceptWaveform(Float32List.sublistView(samples, fedSamples, end));
      fedSamples = end;
      await drainAndRecognize();
      retranscribeProgress = fedSamples / samples.length * 0.9;
      _updateRetranscribeEta(sw, retranscribeProgress / 0.9);
      if (++windows % windowsPerYield == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    _vad.flush();
    await drainAndRecognize();
    retranscribeProgress = 0.9;
    _vad.free();
  }

  void _startRetranscribeTicker() {
    _retranscribeTicker?.cancel();
    _retranscribeTicker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!retranscribing) return t.cancel();
      if (retranscribePaused) return;
      retranscribeElapsedSec++;
      notifyListeners();
    });
  }

  void _updateRetranscribeEta(Stopwatch sw, double ratio) {
    if (ratio > 0.02) {
      final total = sw.elapsed.inSeconds / ratio;
      retranscribeEtaSec = (total - sw.elapsed.inSeconds).round().clamp(
        0,
        24 * 3600,
      );
    }
  }

  // —— 内部 ——

  void _onSamples(Float32List samples) {
    if (phase != RealtimePhase.recording || paused) return;
    _chunks.add(samples);
    _totalSamples += samples.length;

    // 波形幅度
    var peak = 0.0;
    for (var i = 0; i < samples.length; i += 4) {
      final v = samples[i].abs();
      if (v > peak) peak = v;
    }
    liveWave.removeAt(0);
    liveWave.add(peak.clamp(0.0, 1.0));

    _feeder?.feed(samples);
    _drainVad();
    notifyListeners();
  }

  void _onWindow(Float32List window) {
    if (phase == RealtimePhase.recording && !paused) {
      _vad.acceptWaveform(window);
    }
  }

  void _drainVad() {
    while (_vad.hasSegment) {
      final s = _vad.front();
      _enqueue(s.samples, s.start);
      _vad.pop();
    }
  }

  /// 串行识别队列：保证逐句按序输出。
  void _enqueue(Float32List speechSamples, int startSample) {
    _queue = _queue.then((_) async {
      if (models.asr.ready) {
        recognizing = true;
        notifyListeners();
        try {
          final text = await models.asr.recognize(
            speechSamples,
            // 与上传页一致：开关打开且检测到标点模型时启用标点恢复
            punctuate: punctuationEnabled,
          );
          if (text.isNotEmpty) {
            segments.add(
              TranscriptSegment(
                startSec: startSample / VadEngine.sampleRate,
                endSec:
                    (startSample + speechSamples.length) / VadEngine.sampleRate,
                text: text,
              ),
            );
          }
        } catch (e) {
          debugPrint('实时识别失败: $e');
        }
        recognizing = false;
        notifyListeners();
      }
      // 每句识别完成后尝试发起增量说话人分离（节流条件内部判断）
      _maybeStartIncrementalDiarization();
    });
  }

  /// 录音中增量说话人分离：分离只依赖音频，对已录制的音频前缀后台
  /// 跑一轮分离，完成后立即回填标签到已识别段落，实现「边录边识别
  /// 说话人」；录音结束时的全量分离仍会重跑一次并以其结果为准
  /// （全量聚类保证说话人编号全程一致）。
  Future<void> _maybeStartIncrementalDiarization() async {
    if (_incrDiarBusy || !recording || paused || _stopping) return;
    if (!_sessionDiarize || !models.diarizationAvailable) return;
    final durationSec = _totalSamples / VadEngine.sampleRate;
    if (durationSec < _incrDiarIntervalSec ||
        durationSec - _incrDiarMarkSec < _incrDiarIntervalSec) {
      return;
    }
    final gen = _sessionGen;
    _incrDiarBusy = true;
    _incrDiarMarkSec = durationSec;
    liveDiarizing = true;
    notifyListeners();
    try {
      final ok = await models.ensureDiarization();
      // 等待加载/计算期间可能已停止录音或开启新会话，结果作废
      if (!ok || !recording || gen != _sessionGen) return;
      final diarSegs = await models.diarization.process(_snapshotSamples());
      if (!recording || gen != _sessionGen || diarSegs.isEmpty) return;
      segments = assignSpeakers(
        segments: segments,
        diarSegments: [
          for (final d in diarSegs)
            (start: d.start, end: d.end, speaker: d.speaker),
        ],
      );
      notifyListeners();
    } catch (e) {
      debugPrint('增量说话人分离失败: $e');
    } finally {
      _incrDiarBusy = false;
      if (gen == _sessionGen) {
        liveDiarizing = false;
        notifyListeners();
      }
    }
  }

  /// 非破坏性合并已录制音频（录音仍在继续，不能复用会清空缓冲的
  /// [_mergeChunks]）。
  Float32List _snapshotSamples() {
    final out = Float32List(_totalSamples);
    var offset = 0;
    for (final c in _chunks) {
      out.setAll(offset, c);
      offset += c.length;
    }
    return out;
  }

  Float32List _mergeChunks() {
    final out = Float32List(_totalSamples);
    var offset = 0;
    for (final c in _chunks) {
      out.setAll(offset, c);
      offset += c.length;
    }
    _chunks.clear();
    return out;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _retranscribeTicker?.cancel();
    _recorder.stop();
    _vad.free();
    seekRequest.dispose();
    super.dispose();
  }
}
