# 离线语音工作台

完全离线的桌面语音转写应用（**macOS / Windows / Linux**），基于 Flutter + [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx)：

- **FireRedAsr2 AED** —— 中英文（含 20+ 方言）离线语音识别
- **Silero VAD** —— 语音活动检测（长音频分段 / 实时断句）
- **Pyannote Segmentation + 3D-Speaker ERes2Net** —— 说话人分离，转写结果带「说话人 1/2」标签
- **CT-Transformer**（可选）—— 标点恢复（「数字与标点规范化」）

界面按 `docs/设计图` 还原：「上传音频」（拖拽/选择文件、进度、带时间戳与播放条的结果）与「实时转写」（逐句出字、录音波形、会话历史）双 Tab，左侧栏提供历史记录与模型管理。

## 快速开始

```bash
flutter pub get
./scripts/download_models.sh        # 下载离线模型（约 1.5GB，详见 docs/MODELS.md）
flutter run -d macos                # -d windows / -d linux
```

首次启动后在应用左下角「加载模型」面板选择模型目录并加载。

## 构建

```bash
flutter build macos      # 或 windows / linux
flutter test             # 22 个单元/组件测试
```

详细模型下载、放置方式与平台依赖说明见 [docs/MODELS.md](docs/MODELS.md)。

## 发布

推送 `v*` 标签（须与 pubspec.yaml 的 `version` 一致，如 `v1.0.0`）触发
[GitHub Actions](.github/workflows/release.yml)：自动构建 **Windows x64 / macOS
(Apple Silicon) / Linux x64** 三平台产物（均内置全部离线模型，约 1.4GB），
并发布到 GitHub Releases。Linux 产物在 debian:buster（glibc 2.28）容器中构建，
兼容统信 UOS 20 等旧 glibc 系统。手动 `workflow_dispatch` 可试构建（不发布）。
