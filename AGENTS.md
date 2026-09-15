# AGENTS.md — 离线语音工作台（VoxDesk）

完全离线的桌面语音转写应用（**macOS / Windows / Linux**），Flutter + [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx)：
FireRedAsr2 AED（中英文 ASR）、Silero VAD、Pyannote + 3D-Speaker（说话人分离）、CT-Transformer（可选标点恢复）。

## 常用命令

以下命令封装在 **Makefile** 中（`make help` 查看全部；`make run`/`make build` 按当前平台自动选择目标，Flutter 不支持交叉编译）：

```bash
make deps                          # flutter pub get
make analyze                       # lint/静态检查（flutter_lints 6）
make test                          # 单元/组件测试（test/）
make run                           # 或 make run-macos / run-windows / run-linux
make build                         # 或 make build-macos / build-windows / build-linux
make models                        # 下载离线模型到 ./models（约 1.5GB，Windows 用 .ps1）
```

交叉构建：Windows/macOS 目标只能在对应系统上构建（Flutter 无交叉编译路径）；Linux 目标可在 macOS 上经 Docker 构建——`make linux-image` + `make build-linux-docker`（见 `docker/linux-builder.Dockerfile`，下载全走国内镜像，pub 缓存用独立命名卷 `voxdesk-pub-cache`、不与宿主机 `~/.pub-cache` 共享）。构建镜像基于 debian:buster（glibc 2.28），使产物兼容统信 UOS 20 等旧 glibc 系统；Flutter SDK 不进镜像，运行时挂载宿主机 `.flutter/` 克隆（TUNA 镜像的 stable 分支）。产物架构随容器（Apple Silicon 为 linux-arm64）；构建完成后自动把 bundle（含内置模型）打成 `build/voxdesk-linux-<架构>-v<版本>.tar.gz`，解压得到 `voxdesk/` 目录。

模型随应用打包：`make build*` 在 Flutter 构建完成后自动调用 `scripts/bundle_models.sh`，把 `./models` 中引擎所需模型拷进产物（Linux/Windows 为 `data/models/`，macOS 为 `Contents/Resources/models/`，自动排除 `source/`、`audio/`、`test_wavs/` 等非引擎资源）。运行时 `ModelManager` 的查找顺序为：上次手动选择的目录 → 应用内置模型 → 默认文档目录，因此打包版开箱即用；构建前需保证 `./models` 已就绪（`make models`）。模型下载、放置布局与平台依赖详见 **docs/MODELS.md**（改动模型加载逻辑前必读）。

GitHub 发布（程序与模型分开打包）：推 `v*` 标签（须与 pubspec.yaml 的 `version` 一致，不一致会构建失败）触发 `.github/workflows/release.yml`，构建 Windows x64 / macOS（Apple Silicon）/ Linux x64 + arm64 **程序包**（约 100MB，不含模型）与各平台**安装包**——Windows Inno Setup `-setup.exe`（`packaging/windows-installer.iss`，该文件须保持带 BOM 的 UTF-8）、Linux `.deb`（`scripts/build_deb.sh`，装到 /opt/VoxDesk + 桌面菜单项）、macOS `.dmg`；安装包与免安装压缩包出自同一份构建产物，一并发布到 GitHub Releases（骨架参照 sherpa-onnx 官方 flutter 流水线）；推 `models-v*` 标签或手动触发 `.github/workflows/models.yml` 单独打包全部离线模型为 `voxdesk-models-v<版本>.tar.gz`（约 1.4GB，与平台无关）发布到 models-v* 系列 Release。模型放置的三种方式见发布说明（应用内选择 / 文档目录 VoxDesk/models / 并入程序包 data|Resources），与 `ModelManager` 的查找顺序一致；本地 `make build` 仍会把 ./models 内置。CI 固定 Flutter 版本见工作流内 `FLUTTER_VERSION`（升级本地 .flutter 后需同步）。Linux job 在 debian:buster 容器内构建保证产物 glibc ≤ 2.28，并用 objdump 校验产物最高 GLIBC 符号版本，勿把该 job 换回高版本 glibc 的环境；Linux 按 x64 / arm64 矩阵跑在 ubuntu-latest / ubuntu-24.04-arm 上（Flutter 无交叉编译、且官方不发 linux-arm64 SDK tarball，arm64 腿用 git 克隆装 SDK）。

## 架构分层（lib/）

依赖方向：`pages/widgets → state → services → data/core`，services 不反向依赖 state/widgets。

- `data/transcript_models.dart` — 转写段/历史条目等纯数据模型。
- `services/` — 纯 Dart 服务层：
  - `asr_engine.dart` / `diarization_engine.dart` — 后台 Isolate 引擎，通过「加载一次、逐句请求」的消息协议复用；
  - `vad_engine.dart` — Silero VAD 封装 + 512 采样窗口的流式切块（VadWindowFeeder）；
  - `model_manager.dart` — 模型目录宽容扫描（按文件名特征递归匹配，兼容 tarball 嵌套目录）；
  - `history_service.dart` — 历史持久化：`<文档目录>/VoxDesk/history/<id>/`（meta.json、transcript.json、session.wav）；
  - `audio_decode_service.dart` / `wav_io.dart` / `recorder_service.dart` / `docx_exporter.dart`。
- `state/` — ChangeNotifier 控制器，在 `main.dart` 用 MultiProvider 装配：`ModelController`（模型发现/加载）、`HistoryController`、`UploadController`（状态机 idle→fileSelected→transcribing→done）、`RealtimeController`（idle→recording→ended）。保存历史后由 `onHistorySaved` 回调刷新侧边栏。
- `widgets/` + `pages/home_page.dart` — 双 Tab UI（上传音频 / 实时转写），左侧栏为历史与模型管理。界面按 `docs/设计图/` 还原，全部文案为中文。

## 关键约束与陷阱

- **每个 Isolate 都必须单独调用 `sherpa.initBindings()`**（main.dart 主 isolate 与各 worker isolate 内均如此），漏掉会崩溃。
- FireRedAsr2 encoder int8 约 780MB，模型加载与解码必须在 Isolate 中进行，不得阻塞 UI 线程。
- 所有音频统一 **16kHz 单声道**（采集为 PCM16，引擎内部用 Float32List）。
- 实时会话先写 `RealtimeSessionDraft` 草稿（录音已落盘但不进历史列表），说话人标注完成后调 `HistoryService.finalizeRealtimeSession` 转正；启动时会清理残留草稿。
- 平台差异：
  - macOS：沙盒已关闭（entitlements 中 app-sandbox=false），声明了麦克风权限；首次用麦会弹系统授权。
  - Windows/Linux：原生标题栏隐藏，窗口控制按钮由应用内 `widgets/title_bar.dart` 提供；macOS 走原生透明标题栏（见 `macos/Runner/MainFlutterWindow.swift`）——改标题栏行为需两端兼顾。
  - Linux：音频解码依赖 GStreamer、录音依赖 PulseAudio/ALSA（需 apt 安装）。
  - Linux 渲染兜底：`docker/linux-launcher.sh` 默认 `FLUTTER_LINUX_RENDERER=software`（引擎软件渲染，不依赖 EGL/OpenGL），Impeller 在 `linux/runner/my_application.cc` 中显式关闭；release 包里 `FLUTTER_ENGINE_SWITCHES` 环境变量机制被引擎裁剪（且它本身是"开关个数 + FLUTTER_ENGINE_SWITCH_N"格式），给引擎传开关只能改 runner 代码。
- `models/` 目录整体被 `.gitignore` 忽略（`/models/`），不提交到远程仓库；模型本体较大，勿用 `-f` 强加。本地构建前用 `make models` 下载；GitHub 流水线（`.github/workflows/release.yml`）在构建时自动执行 `scripts/download_models.*` 现场下载并打包，不依赖仓库内的模型文件。`make build*` 会把 `./models`（排除 source/audio/test_wavs）内置进产物。
- 提交信息惯例：`feat: <中文描述>`。
