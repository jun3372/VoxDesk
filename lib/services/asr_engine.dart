import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'model_manager.dart';

/// ASR 后台引擎。
///
/// FireRedAsr2 AED 模型体量大（encoder int8 约 780MB），必须在独立 Isolate
/// 中加载与解码，避免阻塞 UI 线程。每个 Isolate 都需要单独调用
/// `initBindings()`。通过「加载一次、逐句请求」的消息协议复用引擎实例。
class AsrEngine {
  Isolate? _isolate;
  ReceivePort? _port;
  StreamSubscription<dynamic>? _sub;
  SendPort? _send;

  Map<String, dynamic>? _pendingInit;
  Completer<void>? _readyCompleter;
  final Map<int, Completer<String>> _pending = {};
  int _nextId = 0;

  bool _ready = false;
  bool get ready => _ready;

  /// 加载模型（耗时操作：encoder 约 780MB，首次加载需数秒）。
  Future<void> load({required ModelPaths paths, int numThreads = 2}) async {
    await quit();
    final ready = Completer<void>();
    _readyCompleter = ready;
    _pendingInit = {
      'type': 'init',
      'encoder': paths.encoder,
      'decoder': paths.decoder,
      'tokens': paths.tokens,
      'punctModel': paths.punctuation,
      'numThreads': numThreads,
    };

    final port = ReceivePort();
    _port = port;
    _sub = port.listen(_onMessage);
    _isolate = await Isolate.spawn(_workerMain, port.sendPort);

    return ready.future.timeout(
      const Duration(minutes: 10),
      onTimeout: () => throw Exception('ASR 模型加载超时'),
    );
  }

  /// 识别一段 16kHz 单声道语音，返回文本。
  ///
  /// [punctuate] 为 true 且加载了标点模型时，识别后做标点恢复
  /// （标点模型已随引擎加载一并就绪）。
  Future<String> recognize(Float32List samples, {bool punctuate = false}) {
    if (!_ready) throw StateError('ASR 引擎尚未加载');
    final id = _nextId++;
    final c = Completer<String>();
    _pending[id] = c;
    _send!.send({
      'type': 'recognize',
      'id': id,
      'samples': samples,
      'punctuate': punctuate,
    });
    return c.future;
  }

  Future<void> quit() async {
    if (_send != null && _isolate != null) {
      _send!.send({'type': 'quit'});
      // 给 worker 一点时间清理 FFI 资源
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    _isolate?.kill(priority: Isolate.beforeNextEvent);
    await _sub?.cancel();
    _port?.close();
    for (final c in _pending.values) {
      if (!c.isCompleted) c.complete('');
    }
    _pending.clear();
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
      case 'result':
        final c = _pending.remove(m['id']);
        if (c != null && !c.isCompleted) {
          if (m['error'] != null) {
            c.completeError(Exception(m['error']));
          } else {
            c.complete((m['text'] as String?) ?? '');
          }
        }
    }
  }
}

/// ASR worker 的 Isolate 入口。
Future<void> _workerMain(SendPort initial) async {
  sherpa.initBindings();
  final port = ReceivePort();
  initial.send(port.sendPort);

  sherpa.OfflineRecognizer? recognizer;
  sherpa.OfflinePunctuation? punct;
  String punctModelPath = '';

  await for (final msg in port) {
    final m = msg as Map;
    switch (m['type'] as String) {
      case 'init':
        try {
          final config = sherpa.OfflineRecognizerConfig(
            model: sherpa.OfflineModelConfig(
              fireRedAsr: sherpa.OfflineFireRedAsrModelConfig(
                encoder: m['encoder'] as String,
                decoder: m['decoder'] as String,
              ),
              tokens: m['tokens'] as String,
              numThreads: m['numThreads'] as int,
              debug: false,
              provider: 'cpu',
            ),
          );
          recognizer = sherpa.OfflineRecognizer(config);
          punctModelPath = m['punctModel'] as String;
          // 标点模型随引擎一并就绪，避免首句识别时额外停顿数秒
          if (punctModelPath.isNotEmpty) {
            punct = _loadPunct(punctModelPath);
          }
          initial.send({'type': 'ready'});
        } catch (e) {
          initial.send({'type': 'error', 'message': e.toString()});
        }

      case 'recognize':
        final id = m['id'] as int;
        try {
          final samples = m['samples'] as Float32List;
          final stream = recognizer!.createStream();
          stream.acceptWaveform(samples: samples, sampleRate: 16000);
          recognizer.decode(stream);
          var text = recognizer.getResult(stream).text.trim();
          stream.free();

          if ((m['punctuate'] as bool? ?? false) &&
              text.isNotEmpty &&
              punctModelPath.isNotEmpty) {
            punct ??= _loadPunct(punctModelPath);
            if (punct != null) text = punct.addPunct(text);
          }
          initial.send({'type': 'result', 'id': id, 'text': text});
        } catch (e) {
          initial.send({
            'type': 'result',
            'id': id,
            'text': '',
            'error': e.toString(),
          });
        }

      case 'quit':
        try {
          recognizer?.free();
          punct?.free();
        } catch (_) {}
        initial.send({'type': 'bye'});
        return;
    }
  }
}

sherpa.OfflinePunctuation? _loadPunct(String path) {
  try {
    return sherpa.OfflinePunctuation(
      config: sherpa.OfflinePunctuationConfig(
        model: sherpa.OfflinePunctuationModelConfig(
          ctTransformer: path,
          debug: false,
        ),
      ),
    );
  } catch (_) {
    return null;
  }
}

/// ASR 引擎池：多个 worker Isolate 并发解码，对外暴露与 [AsrEngine]
/// 相同的 `recognize` 接口，请求自动分发到最空闲的 worker。
///
/// 每个 worker 独立加载一份模型（encoder int8 约 780MB），worker 数由
/// 设备算力决定（见 device_tuning.dart），调用方无需关心。
class AsrEnginePool {
  final List<AsrEngine> _workers = [];
  final List<int> _inFlight = [];

  bool _ready = false;
  bool get ready => _ready;

  /// worker 数量（未加载时为 0）。
  int get workerCount => _workers.length;

  /// 并行加载 [workers] 个 worker（并行加载缩短启动时间）。
  Future<void> load({
    required ModelPaths paths,
    int workers = 1,
    int numThreads = 2,
  }) async {
    await quit();
    final count = workers < 1 ? 1 : workers;
    final engines = List.generate(count, (_) => AsrEngine());
    try {
      await Future.wait(
        engines.map((e) => e.load(paths: paths, numThreads: numThreads)),
      );
    } catch (_) {
      await Future.wait(engines.map((e) => e.quit()));
      rethrow;
    }
    _workers
      ..clear()
      ..addAll(engines);
    _inFlight
      ..clear()
      ..addAll(List.filled(count, 0));
    _ready = true;
  }

  /// 识别一段 16kHz 单声道语音，分发到当前在途请求最少的 worker。
  Future<String> recognize(Float32List samples, {bool punctuate = false}) {
    if (!_ready) throw StateError('ASR 引擎尚未加载');
    var best = 0;
    for (var i = 1; i < _workers.length; i++) {
      if (_inFlight[i] < _inFlight[best]) best = i;
    }
    final index = best;
    _inFlight[index]++;
    return _workers[index]
        .recognize(samples, punctuate: punctuate)
        // quit 后挂起请求以空串完成，此时 _inFlight 可能已清空
        .whenComplete(() {
          if (index < _inFlight.length) _inFlight[index]--;
        });
  }

  Future<void> quit() async {
    await Future.wait(_workers.map((e) => e.quit()));
    _workers.clear();
    _inFlight.clear();
    _ready = false;
  }
}
