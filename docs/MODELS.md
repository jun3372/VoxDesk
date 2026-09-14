# 模型下载与放置说明

离线语音工作台是完全离线的应用，所有模型共约 **1.5GB**。

**发布版应用已内置全部模型，开箱即用**，无需下载、也无需在应用内选择模型目录。
只有本地开发（`make run`）或自行构建时才需要先准备 `./models` 目录。

## 一键下载（开发/自构建用）

**macOS / Linux：**

```bash
./scripts/download_models.sh          # 下载到 ./models
./scripts/download_models.sh ~/asr-models   # 或指定目录
```

**Windows（PowerShell）：**

```powershell
.\scripts\download_models.ps1          # 下载到 .\models
.\scripts\download_models.ps1 D:\asr-models
```

> 国内网络若 GitHub 下载缓慢，可用代理或从 HuggingFace 镜像（如 hf-mirror.com）
> 手动下载下列同名模型。

## 模型清单

| 用途 | 模型 | 文件 |
| --- | --- | --- |
| 语音识别（必需） | FireRedAsr2 AED int8 | `encoder.int8.onnx`（约 780MB）、`decoder.int8.onnx`（约 400MB）、`tokens.txt` |
| 语音活动检测（必需） | Silero VAD | `silero_vad.onnx`（约 2MB） |
| 说话人分离（推荐） | Pyannote Segmentation 3.0 | `model.onnx`（约 6MB） |
| 说话人分离（推荐） | 3D-Speaker ERes2Net 嵌入 | `3dspeaker_speech_eres2net_base_sv_zh-cn_3dspeaker_16k.onnx`（约 46MB） |
| 标点恢复（可选） | CT-Transformer 中英文 | `model.onnx`（约 290MB） |

## 放置方式

下载脚本会保留原始解包目录结构，应用对目录结构做了宽容扫描——只要把
下载/解压出来的所有内容放进同一个目录树即可，无需手动整理。推荐布局：

```
models/
├── sherpa-onnx-fire-red-asr2-zh_en-int8-2026-02-26/
│   ├── encoder.int8.onnx
│   ├── decoder.int8.onnx
│   └── tokens.txt
├── silero_vad.onnx
├── sherpa-onnx-pyannote-segmentation-3-0/
│   ├── model.onnx
│   └── model.int8.onnx
├── 3dspeaker_speech_eres2net_base_sv_zh-cn_3dspeaker_16k.onnx
└── sherpa-onnx-punct-ct-transformer-zh-en-vocab272727-2024-04-12/
    └── model.onnx
```

在应用内：左下角「加载模型」面板可查看模型状态。应用的查找顺序为：

1. **上次手动选择的模型目录**（`<文档目录>/VoxDesk/config.json` 中记录）；
2. **应用内置模型**（随安装包分发，见下节）；
3. 默认目录 `<文档目录>/VoxDesk/models`。

## 随应用打包

`make build`（以及 `build-macos` / `build-windows` / `build-linux` /
`build-linux-docker`）在 Flutter 构建完成后会自动调用
`scripts/bundle_models.sh`，把 `./models` 中引擎所需的模型拷进产物：

| 平台 | 内置位置 |
| --- | --- |
| Linux | `<bundle>/data/models/` |
| Windows | `Release/data/models/` |
| macOS | `离线语音工作台.app/Contents/Resources/models/` |

拷贝时自动排除非引擎资源（`source/` 原始下载包、`audio/` 示例音频、各模型
自带的 `test_wavs/`、tarball 等），内置后总体积约 1.5GB。构建前需保证
`./models` 已就绪（`make models`），否则产物不含内置模型，运行时需手动
选择模型目录。

## 手动下载地址

- FireRedAsr2 AED:
  `https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-fire-red-asr2-zh_en-int8-2026-02-26.tar.bz2`
- Silero VAD:
  `https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx`
- Pyannote 分割:
  `https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-segmentation-models/sherpa-onnx-pyannote-segmentation-3-0.tar.bz2`
- 3D-Speaker 嵌入（注意 tag 原文即有拼写错误 `recongition`，需原样复制）:
  `https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-recongition-models/3dspeaker_speech_eres2net_base_sv_zh-cn_3dspeaker_16k.onnx`
- 标点恢复:
  `https://github.com/k2-fsa/sherpa-onnx/releases/download/punctuation-models/sherpa-onnx-punct-ct-transformer-zh-en-vocab272727-2024-04-12.tar.bz2`

## 平台注意事项

- **Linux**：音频解码依赖 GStreamer，录音依赖 PulseAudio/ALSA：
  ```bash
  sudo apt install libgstreamer1.0-dev libpulse-dev libasound2-dev
  ```
- **macOS**：首次使用麦克风时系统会弹窗授权（应用已声明沙盒权限）。
- **Windows**：无需额外依赖（Media Foundation / WASAPI 原生支持）。

## 构建

```bash
flutter pub get
flutter run -d macos      # macOS
flutter run -d windows    # Windows
flutter run -d linux      # Linux
```
