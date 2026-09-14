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
  /// [punctuate] 为 true 且加载了标点模型时，会先延迟加载标点模型再做
  /// 标点恢复（首次调用会额外耗时数秒）。
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
