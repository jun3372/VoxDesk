# 离线语音工作台（VoxDesk）常用命令
#
# 注意：Flutter 不支持交叉编译——macOS 目标只能在 macOS 上构建，
# windows 目标只能在 Windows 上构建，linux 目标只能在 Linux 上构建。
# 用 `make build` / `make run` 可按当前系统自动选择平台。

ifeq ($(OS),Windows_NT)
PLATFORM := windows
else
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
PLATFORM := macos
else
PLATFORM := linux
endif
endif

.DEFAULT_GOAL := help

# 平台守卫：Flutter 不支持交叉编译/跨平台运行，目标与主机不符时直接报错
define host_guard
if [ "$(PLATFORM)" != "$(1)" ]; then \
	echo "✗ $(2) 只能在 $(1) 上执行（当前主机：$(PLATFORM)）——Flutter 不支持交叉编译"; \
	exit 1; \
fi
endef

.PHONY: help deps models analyze test run run-macos run-windows run-linux \
        build build-macos build-windows build-linux \
        linux-image build-linux-docker clean

help: ## 显示可用命令
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

deps: ## 安装依赖（flutter pub get）
	flutter pub get

models: ## 下载离线模型到 ./models（约 1.5GB，Windows 请用 scripts/download_models.ps1）
	./scripts/download_models.sh

analyze: ## 静态检查（flutter analyze）
	flutter analyze

test: ## 运行单元/组件测试
	flutter test

# ---------- 运行 ----------

run: run-$(PLATFORM) ## 运行（按当前平台自动选择）

run-macos: ## 在 macOS 上运行
	$(call host_guard,macos,run-macos)
	flutter run -d macos

run-windows: ## 在 Windows 上运行
	$(call host_guard,windows,run-windows)
	flutter run -d windows

run-linux: ## 在 Linux 上运行
	$(call host_guard,linux,run-linux)
	flutter run -d linux

# ---------- 构建 ----------

build: build-$(PLATFORM) ## 构建 release（按当前平台自动选择）

build-macos: ## 构建 macOS 应用（模型自动内置，产物在 build/macos/Build/Products/Release/）
	$(call host_guard,macos,build-macos)
	flutter build macos
	-./scripts/bundle_models.sh "build/macos/Build/Products/Release/"*.app

build-windows: ## 构建 Windows 应用（模型自动内置，产物在 build/windows/x64/runner/Release/）
	$(call host_guard,windows,build-windows)
	flutter build windows
	-./scripts/bundle_models.sh "build/windows/x64/runner/Release"

build-linux: ## 构建 Linux 应用（模型自动内置，产物在 build/linux/x64/release/bundle/）
	$(call host_guard,linux,build-linux)
	flutter build linux
	-./scripts/bundle_models.sh "build/linux/x64/release/bundle"

# ---------- Docker 交叉构建（在 macOS/Windows 上构建 Linux 版） ----------

linux-image: ## 构建 Docker 交叉编译镜像（buster 基础，适配 UOS 20 / glibc 2.28）
	docker build -t voxdesk-linux-builder -f docker/linux-builder.Dockerfile docker

build-linux-docker: ## 在 Docker 中构建 Linux 版（模型自动内置并打成 tar.gz；产物架构随容器：Apple Silicon 为 arm64）
	# 容器内 pub 缓存使用独立命名卷，不与宿主机 ~/.pub-cache 同路径/共享：
	# 宿主机的 pub 操作不会覆盖容器缓存，容器内的解包产物也不会污染宿主机；
	# 命名卷跨构建持久化，包无需每次重新下载。下载走镜像内配置的国内源。
	#
	# build/ 与 .dart_tool/ 随项目目录在宿主/容器间共享，容器构建前清理
	# linux 产物与宿主（macOS）残留的 hooks 状态。另需预建
	# build/native_assets/linux：objective_c 的 hook 仅在 Apple 平台产出
	# （经 path_provider_foundation 传递引入），Linux 下无产物时 flutter
	# 工具不会创建该目录，但生成的 cmake_install.cmake 又无条件引用它，
	# 不预建则 CMake 安装阶段直接失败。
	docker run --rm -v "$(CURDIR)":/work -w /work \
		-v "$(CURDIR)/.flutter":/opt/flutter \
		-v voxdesk-pub-cache:/pub-cache \
		-e PUB_CACHE=/pub-cache \
		voxdesk-linux-builder sh -c 'rm -rf build/linux build/native_assets .dart_tool/hooks_runner \
			&& mkdir -p build/native_assets/linux \
			&& flutter pub get && flutter build linux \
			&& BUNDLE=$$(find build/linux -type d -path "*release/bundle" | head -1) \
			&& mv $$BUNDLE/voxdesk $$BUNDLE/voxdesk.bin \
			&& cp /work/docker/linux-launcher.sh $$BUNDLE/voxdesk && chmod +x $$BUNDLE/voxdesk \
			&& bash scripts/bundle_stdlib.sh "$$BUNDLE"'
	-./scripts/bundle_models.sh "$$(find build/linux -type d -path '*release/bundle' | head -1)"
	# 打成发布压缩包：bundle 目录改名为 voxdesk（解压得到 voxdesk/，兼容
	# macOS bsdtar 与 Linux GNU tar），版本号取自 pubspec.yaml，架构取
	# 自产物路径（build/linux/<arch>/release/bundle）。
	# --no-xattrs 必须带：macOS bsdtar 默认把 quarantine/provenance 等
	# 扩展属性写进 PAX 头，Windows/Linux 的部分解压工具（7-Zip/WinRAR
	# 等）不识别，会把它们物化成一堆 ._xxx 文件。
	BUNDLE=$$(find build/linux -type d -path '*release/bundle' | head -1); \
	[ -n "$$BUNDLE" ] || { echo "✗ 未找到 Linux 构建产物"; exit 1; }; \
	ARCH=$$(echo "$$BUNDLE" | awk -F/ '{print $$3}'); \
	VER=$$(sed -nE 's/^version:[[:space:]]*([0-9.]+).*/\1/p' pubspec.yaml | head -1); \
	VER=$${VER:-dev}; \
	mv "$$BUNDLE" "$$(dirname "$$BUNDLE")/voxdesk" && \
	tar --exclude='._*' --exclude='.DS_Store' --no-xattrs \
		-czf "build/voxdesk-linux-$$ARCH-v$$VER.tar.gz" -C "$$(dirname "$$BUNDLE")" voxdesk && \
	echo "✓ 压缩包已生成：build/voxdesk-linux-$$ARCH-v$$VER.tar.gz ($$(du -sh "build/voxdesk-linux-$$ARCH-v$$VER.tar.gz" | cut -f1))"

clean: ## 清理构建产物
	flutter clean
