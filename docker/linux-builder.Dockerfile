# Linux 构建环境：在 macOS 上通过 Docker 构建 Linux 桌面版。
#
# 用法（宿主机项目根目录）：
#   make linux-image          # 构建镜像（仅系统工具链）
#   make build-linux-docker   # 在容器中构建 Linux 版
#
# 兼容性：基础镜像 debian:buster 的 glibc 为 2.28，与目标系统
# 统信 UOS 20（glibc 2.28.x-deepin）一致；在更高版本 glibc 的镜像
# （如 ubuntu:24.04 / glibc 2.39）中构建的产物无法在 UOS 20 上运行。
# Flutter 工具链（dart / gen_snapshot，GLIBC_2.18）与官方 engine 产物
# （libflutter_linux_gtk.so，GLIBC_2.18）均满足 2.28。
#
# Flutter SDK 不打进镜像：运行时把宿主机的 .flutter 克隆
# （https://mirrors.tuna.tsinghua.edu.cn/git/flutter-sdk.git，stable 分支）
# 挂载到 /opt/flutter；Dart SDK 与构建产物缓存由 flutter 工具在首次运行时
# 从 FLUTTER_STORAGE_BASE_URL 下载，写回宿主机的 .flutter/bin/cache 复用。
#
# 所有下载均优先使用国内镜像：apt（阿里云 debian-archive，buster 已 EOL）、
# pip（清华 PyPI）、Flutter SDK 仓库（清华 TUNA git 镜像）、
# engine 构建产物（storage.flutter-io.cn）。
FROM debian:buster

# Flutter / pub 官方中国镜像（Flutter 团队与社区维护）；
# SDK 仓库走清华 TUNA git 镜像（FLUTTER_GIT_URL 亦为 flutter 工具识别的变量）
ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn \
    PUB_HOSTED_URL=https://pub.flutter-io.cn \
    FLUTTER_GIT_URL=https://mirrors.tuna.tsinghua.edu.cn/git/flutter-sdk.git \
    PATH="/opt/flutter/bin:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin"

# apt 换阿里云 debian-archive 镜像（buster 已 EOL，从常规源下架；
# 基础镜像尚无 ca-certificates，故用 http——Release 文件带 GPG 签名，
# 完整性不受传输方式影响）
RUN printf '%s\n' \
      'deb http://mirrors.aliyun.com/debian-archive/debian buster main' \
      'deb http://mirrors.aliyun.com/debian-archive/debian buster-updates main' \
      'deb http://mirrors.aliyun.com/debian-archive/debian-security buster/updates main' \
      > /etc/apt/sources.list

RUN apt-get update && apt-get install -y --no-install-recommends \
      # Flutter Linux 桌面构建标配（flutter 工具强制 CC/CXX=clang，最低 3.4）
      clang build-essential pkg-config libgtk-3-dev liblzma-dev \
      # 插件原生依赖的开发头：GStreamer（audio_decoder / audioplayers）、
      # PulseAudio/ALSA（record）
      libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
      libpulse-dev libasound2-dev \
      # 通用工具（flutter 工具自身依赖 git）
      git curl ca-certificates unzip xz-utils zip python3-pip \
    && rm -rf /var/lib/apt/lists/*

# 新版 cmake/ninja：buster 自带 cmake 3.13 过旧，部分 Flutter 插件模板要求更高版本
RUN python3 -m pip install --upgrade pip \
      -i https://pypi.tuna.tsinghua.edu.cn/simple \
    && python3 -m pip install cmake ninja \
      -i https://pypi.tuna.tsinghua.edu.cn/simple

# 挂载宿主目录（项目仓库与 .flutter SDK 克隆均属宿主用户）时，
# 避免 git 对属主的告警
RUN git config --global --add safe.directory /opt/flutter \
    && git config --global --add safe.directory '*'

WORKDIR /work
