import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'model_manager.dart';

/// 说话人分离结果段（时间单位：秒）。
class DiarSegment {
  const DiarSegment({
    required this.start,
    required this.end,
    required this.speaker,
  });

  final double start;
  final double end;
  final int speaker;
}

/// 说话人分离后台引擎（Pyannote segmentation + 3D-Speaker ERes2Net 嵌入）。
///
/// 全量音频一次处理，进度通过回调消息回传。
class DiarizationEngine {
  Isolate? _isolate;
  ReceivePort? _port;
  StreamSubscription<dynamic>? _sub;
  SendPort? _send;

  Map<String, dynamic>? _pendingInit;
  Completer<void>? _readyCompleter;
  Completer<List<DiarSegment>>? _processCompleter;
  void Function(int done, int total)? _onProgress;

  /// 串行队列：引擎一次只能跑一个计算，多个调用按提交顺序执行。
  Future<void> _sendQueue = Future.value();

  bool _ready = false;
  bool get ready => _ready;

  Future<void> load({required ModelPaths paths, int numThreads = 2}) async {
    await quit();
    final ready = Completer<void>();
    _readyCompleter = ready;
    _pendingInit = {
      'type': 'init',
      'pyannote': paths.pyannoteSegmentation,
      'embedding': paths.speakerEmbedding,
      'numThreads': numThreads,
    };

    final port = ReceivePort();
    _port = port;
    _sub = port.listen(_onMessage);
    _isolate = await Isolate.spawn(_workerMain, port.sendPort);

    return ready.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () => throw Exception('说话人分离模型加载超时'),
    );
  }

  /// 处理完整 16kHz 音频，返回说话人段列表。
  /// 多个调用按提交顺序串行执行。
  ///
  /// [transfer] 为 true 时采样缓冲零拷贝移交给 worker isolate，
  /// 调用后调用方持有的 [samples] 立即失效、不得再使用；
  /// 仅当音频为本次调用专门准备（如刚从磁盘读出）时才能开启。
  Future<List<DiarSegment>> process(
    Float32List samples, {
    void Function(int done, int total)? onProgress,
    bool transfer = false,
  }) {
    final run = _sendQueue.then((_) {
      if (!_ready) throw StateError('说话人分离引擎尚未加载');
      _onProgress = onProgress;
      final c = _processCompleter = Completer<List<DiarSegment>>();
      _send!.send({
        'type': 'process',
        'samples': transfer
            ? TransferableTypedData.fromList([
                samples.buffer.asUint8List(
                  samples.offsetInBytes,
                  samples.length * 4,
                ),
              ])
            : samples,
      });
      return c.future;
    });
    _sendQueue = run.then((_) {}, onError: (_) {});
    return run;
  }

  /// 请求中止当前计算；下次 process 开始时会自动复位，无副作用。
  void cancel() => _send?.send({'type': 'cancel'});

  Future<void> quit() async {
    if (_send != null && _isolate != null) {
      _send!.send({'type': 'quit'});
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    _isolate?.kill(priority: Isolate.beforeNextEvent);
    await _sub?.cancel();
    _port?.close();
    _isolate = null;
    _port = null;
    _sub = null;
    _send = null;
    _ready = false;
  }

  void _onMessage(dynamic msg) {
    if (msg is SendPort) {
      _send = msg;
      _send!.send(_pendingInit);
      return;
    }
    final m = msg as Map;
    switch (m['type'] as String) {
      case 'ready':
        _ready = true;
        _readyCompleter?.complete();
      case 'error':
        _ready = false;
        _readyCompleter?.completeError(Exception(m['message']));
      case 'progress':
        _onProgress?.call(m['done'] as int, m['total'] as int);
      case 'done':
        final segs = (m['segments'] as List)
            .map(
              (e) => DiarSegment(
                start: (e['start'] as num).toDouble(),
                end: (e['end'] as num).toDouble(),
                speaker: e['speaker'] as int,
              ),
            )
            .toList();
        _processCompleter?.complete(segs);
        _processCompleter = null;
    }
  }
}

/// 说话人分离 worker 的 Isolate 入口。
Future<void> _workerMain(SendPort initial) async {
  sherpa.initBindings();
  final port = ReceivePort();
  initial.send(port.sendPort);

  sherpa.OfflineSpeakerDiarization? diar;
  var cancelRequested = false;

  await for (final msg in port) {
    final m = msg as Map;
    switch (m['type'] as String) {
      case 'init':
        try {
          final config = sherpa.OfflineSpeakerDiarizationConfig(
            segmentation: sherpa.OfflineSpeakerSegmentationModelConfig(
              pyannote: sherpa.OfflineSpeakerSegmentationPyannoteModelConfig(
                model: m['pyannote'] as String,
              ),
            ),
            embedding: sherpa.SpeakerEmbeddingExtractorConfig(
              model: m['embedding'] as String,
              numThreads: m['numThreads'] as int,
              debug: false,
            ),
            clustering: const sherpa.FastClusteringConfig(
              numClusters: -1,
              threshold: 0.65,
            ),
            minDurationOn: 0.3,
            minDurationOff: 0.6,
          );
          diar = sherpa.OfflineSpeakerDiarization(config);
          initial.send({'type': 'ready'});
        } catch (e) {
          initial.send({'type': 'error', 'message': e.toString()});
        }

      case 'process':
        cancelRequested = false;
        try {
          final raw = m['samples'];
          final samples = raw is TransferableTypedData
              ? raw.materialize().asFloat32List()
              : raw as Float32List;
          final segs = diar!.processWithCallback(
            samples: samples,
            // 回调返回非 0 时 sherpa-onnx 中止本次计算
            callback: (done, total) {
              initial.send({'type': 'progress', 'done': done, 'total': total});
              return cancelRequested ? 1 : 0;
            },
          );
          initial.send({
            'type': 'done',
            'segments': [
              for (final s in segs)
                {'start': s.start, 'end': s.end, 'speaker': s.speaker},
            ],
          });
        } catch (e) {
          // 失败时返回空结果，不中断整体转写流程
          initial.send({'type': 'done', 'segments': <Map<String, dynamic>>[]});
        }

      case 'cancel':
        cancelRequested = true;

      case 'quit':
        try {
          diar?.free();
        } catch (_) {}
        initial.send({'type': 'bye'});
        return;
    }
  }
}
