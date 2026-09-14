import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:voxdesk/services/model_manager.dart';

void main() {
  group('ModelManager 内置模型目录推导', () {
    test('Linux/Windows：可执行文件旁 data/models', () {
      final candidates = ModelManager.bundledCandidates(
        '/opt/voxdesk/bundle/voxdesk.bin',
        isMacOS: false,
      );
      expect(candidates, ['/opt/voxdesk/bundle/data/models']);
    });

    test('macOS：Contents/Resources/models', () {
      final candidates = ModelManager.bundledCandidates(
        '/Applications/voxdesk.app/Contents/MacOS/voxdesk',
        isMacOS: true,
      );
      expect(candidates, ['/Applications/voxdesk.app/Contents/Resources/models']);
    });

    test('Windows 反斜杠路径同样推导出 data/models', () {
      final candidates = ModelManager.bundledCandidates(
        'C:\\apps\\voxdesk\\Release\\voxdesk.exe',
        isMacOS: false,
      );
      expect(candidates.single, contains('data'));
      expect(candidates.single, endsWith('models'));
    });

    test('bundledDir：候选目录不存在时返回 null', () {
      // 测试进程的可执行文件旁没有 data/models 或 Resources/models
      expect(ModelManager.bundledDir(isMacOS: false), isNull);
      expect(ModelManager.bundledDir(isMacOS: true), isNull);
    });

    test('scanBundled：无内置模型时返回 null 且不抛异常', () async {
      final manager = ModelManager();
      expect(await manager.scanBundled(isMacOS: false), isNull);
    });
  });

  group('ModelManager.scan', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('voxdesk_models_test');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('嵌套 tarball 目录布局可完整识别五类模型', () async {
      final asr = Directory(
        '${tempDir.path}/sherpa-onnx-fire-red-asr2-zh_en-int8-2026-02-26',
      )..createSync(recursive: true);
      File('${asr.path}/encoder.int8.onnx').writeAsStringSync('e');
      File('${asr.path}/decoder.int8.onnx').writeAsStringSync('d');
      File('${asr.path}/tokens.txt').writeAsStringSync('t');
      File('${tempDir.path}/silero_vad.onnx').writeAsStringSync('v');
      final pyannote = Directory(
        '${tempDir.path}/sherpa-onnx-pyannote-segmentation-3-0',
      )..createSync(recursive: true);
      File('${pyannote.path}/model.onnx').writeAsStringSync('p');
      File(
        '${tempDir.path}/3dspeaker_speech_eres2net_base_sv_zh-cn_3dspeaker_16k.onnx',
      ).writeAsStringSync('s');
      final punct = Directory(
        '${tempDir.path}/sherpa-onnx-punct-ct-transformer-zh-en-vocab272727',
      )..createSync(recursive: true);
      File('${punct.path}/model.onnx').writeAsStringSync('u');

      final paths = await ModelManager().scan(tempDir.path);
      expect(paths, isNotNull);
      expect(paths!.asrReady, isTrue);
      expect(paths.vadReady, isTrue);
      expect(paths.diarizationReady, isTrue);
      expect(paths.punctuationReady, isTrue);
      expect(paths.bundled, isFalse);
      // tokens.txt 与 encoder 同目录就近绑定
      expect(
        File(paths.tokens).parent.path,
        File(paths.encoder).parent.path,
      );
    });

    test('跳过 AppleDouble 等隐藏文件，只匹配真模型', () async {
      // 模拟从 Mac 拷贝模型目录后混入的 ._*/.DS_Store 元数据文件
      File(
        '${tempDir.path}/._3dspeaker_speech_eres2net_base_sv_zh-cn_3dspeaker_16k.onnx',
      ).writeAsStringSync('junk');
      File('${tempDir.path}/.DS_Store').writeAsStringSync('junk');
      File('${tempDir.path}/._silero_vad.onnx').writeAsStringSync('junk');
      final sub = Directory('${tempDir.path}/3dspeaker')..createSync();
      final realEmbedding = File(
        '${sub.path}/3dspeaker_speech_eres2net_base_sv_zh-cn_3dspeaker_16k.onnx',
      )..writeAsStringSync('real');
      final vad = File(
        '${tempDir.path}/silero_vad.onnx',
      )..writeAsStringSync('vad');

      final paths = await ModelManager().scan(tempDir.path);
      expect(paths, isNotNull);
      expect(paths!.speakerEmbedding, realEmbedding.path);
      expect(paths.sileroVad, vad.path);
    });

    test('bundled 标记透传给扫描结果', () async {
      final asr = Directory('${tempDir.path}/fire')..createSync(recursive: true);
      File('${asr.path}/encoder.int8.onnx').writeAsStringSync('e');
      File('${asr.path}/decoder.int8.onnx').writeAsStringSync('d');
      File('${asr.path}/tokens.txt').writeAsStringSync('t');
      File('${tempDir.path}/silero_vad.onnx').writeAsStringSync('v');

      final paths = await ModelManager().scan(tempDir.path, bundled: true);
      expect(paths!.bundled, isTrue);
      expect(paths.coreReady, isTrue);
    });

    test('目录不存在返回 null', () async {
      final paths = await ModelManager().scan('${tempDir.path}/nope');
      expect(paths, isNull);
    });
  });

  group('ModelManager.resolveScan', () {
    late Directory tempDir;
    late Directory asrDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('voxdesk_resolve_test');
      asrDir = Directory(
        '${tempDir.path}/sherpa-onnx-fire-red-asr2-zh_en-int8-2026-02-26',
      )..createSync(recursive: true);
      File('${asrDir.path}/encoder.int8.onnx').writeAsStringSync('e');
      File('${asrDir.path}/decoder.int8.onnx').writeAsStringSync('d');
      File('${asrDir.path}/tokens.txt').writeAsStringSync('t');
      File('${tempDir.path}/silero_vad.onnx').writeAsStringSync('v');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('核心齐备的目录直接返回，不向上回溯', () async {
      final paths = await ModelManager().resolveScan(tempDir.path);
      expect(paths!.coreReady, isTrue);
      expect(paths.dir, tempDir.path);
    });

    test('选中深层模型文件时归位到模型根目录', () async {
      final encoderFile = File('${asrDir.path}/encoder.int8.onnx');
      final paths = await ModelManager().resolveScan(encoderFile.path);
      expect(paths!.coreReady, isTrue);
      expect(paths.dir, tempDir.path);
      expect(paths.sileroVad, '${tempDir.path}/silero_vad.onnx');
    });

    test('选中只含部分模型的嵌套子目录时向上找到模型根目录', () async {
      final paths = await ModelManager().resolveScan(asrDir.path);
      expect(paths!.coreReady, isTrue);
      expect(paths.dir, tempDir.path);
    });

    test('选中无任何模型特征的文件时停在起始层，不向上扫大目录', () async {
      final bare = Directory.systemTemp.createTempSync('voxdesk_bare_test');
      try {
        final sub = Directory('${bare.path}/a/b')..createSync(recursive: true);
        File('${sub.path}/x.txt').writeAsStringSync('hi');
        final paths = await ModelManager().resolveScan('${sub.path}/x.txt');
        expect(paths, isNotNull);
        expect(paths!.coreReady, isFalse);
        expect(paths.dir, sub.path);
      } finally {
        bare.deleteSync(recursive: true);
      }
    });
  });
}
