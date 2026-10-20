#!/bin/sh
# UOS 20 / 云桌面兼容启动器（构建时由 Makefile 拷贝到 bundle 根目录）。
#
# 背景：目标机的 GL 栈不可控——云桌面/虚拟机没有 GPU 驱动，UOS 20 自带的
# Mesa 较老且常缺 EGL 实现，而 Flutter Linux (GTK) 渲染强制依赖 EGL，
# EGL 上下文建不出来时窗口黑屏（对应日志 "Failed to create EGL context"）。
#
# FLUTTER_LINUX_RENDERER=software 走引擎自带的软件渲染路径
# （CPU 位图 + Cairo 上屏），完全不依赖 EGL/OpenGL/GLX，任何环境都能出画面。
# 有 GPU 且驱动正常的机器可启动时覆盖回硬件渲染：
#   FLUTTER_LINUX_RENDERER=opengl ./voxdesk
#   # 若此时硬件 EGL 仍不可用，可再加 LIBGL_ALWAYS_SOFTWARE=1 走 Mesa 软件渲染
#
# Impeller 已在 linux/runner/my_application.cc 里显式关闭。注意：release 包中
# FLUTTER_ENGINE_SWITCHES 环境变量机制被引擎整个裁剪（含
# FLUTTER_ENGINE_SWITCH_N），想给引擎传开关只能改 runner 代码，写环境变量无效。
# ASR/VAD 计算走 CPU（onnxruntime），不受软件渲染影响。
cd "$(dirname "$0")" || exit 1

export FLUTTER_LINUX_RENDERER="${FLUTTER_LINUX_RENDERER:-software}"

# 优先加载随包内置的 libstdc++/libgcc（scripts/bundle_stdlib.sh 拷入 lib/）：
# glibc ≥ 2.18 的老发行版（Ubuntu 16.04 等）系统 libstdc++ 低于产物要求的
# GLIBCXX_3.4.22；新系统上亦无碍，库仅对本进程生效
LD_LIBRARY_PATH="$(pwd)/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export LD_LIBRARY_PATH

exec ./voxdesk.bin "$@"
