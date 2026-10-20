#!/usr/bin/env bash
# 把构建容器内的 libstdc++ / libgcc_s 拷入 bundle/lib，随包分发。
#
# 背景：产物（libaudio_decoder_plugin.so 等）对 libstdc++ 的要求最高到
# GLIBCXX_3.4.22，而 glibc ≥ 2.18 的老发行版（Ubuntu 16.04、Debian 8 等）
# 系统自带的 libstdc++ 往往更旧（Ubuntu 16.04 仅 3.4.21），加载时直接报
# 「version GLIBCXX_3.4.22 not found」。构建容器 debian:buster 的
# libstdc++.so.6.0.25 自身最高只引用 GLIBC_2.18，随包分发即可满足全部
# GLIBCXX/CXXABI 要求，且不突破 glibc 2.18 红线（CI 校验会兜底）。
#
# 启动器（docker/linux-launcher.sh）把 bundle/lib 前置到 LD_LIBRARY_PATH，
# 运行时优先加载随包副本；新系统上系统库更新也无碍（仅对本进程生效）。
# GTK / GStreamer / PulseAudio / ALSA 均为纯 C，不受影响。
#
# 用法（需在构建容器内执行，依赖 objdump）：scripts/bundle_stdlib.sh <bundle目录>
set -euo pipefail

BUNDLE=$1
[ -d "$BUNDLE/lib" ] || { echo "✗ $BUNDLE/lib 不存在" >&2; exit 1; }
MAX_GLIBC=2.18

# buster 下 libstdc++ 装在 /usr/lib/<triplet>，libgcc_s 装在 /lib/<triplet>；
# 按通配匹配以同时兼容 x64 / arm64 容器
pick() { { ls "$@" 2>/dev/null || true; } | head -1; }

STD=$(pick /usr/lib/*/libstdc++.so.6* /lib/*/libstdc++.so.6*)
GCC=$(pick /usr/lib/*/libgcc_s.so.1 /lib/*/libgcc_s.so.1)
[ -n "$STD" ] && [ -n "$GCC" ] || { echo "✗ 容器内未找到 libstdc++ / libgcc_s" >&2; exit 1; }

# 符号链接拷成实体，bundle 内不保留 .so.6 -> .so.6.0.25 链式结构
cp -L "$STD" "$BUNDLE/lib/libstdc++.so.6"
cp -L "$GCC" "$BUNDLE/lib/libgcc_s.so.1"

# 自检：随包副本自身不得突破 glibc 红线，否则老系统上反而加载失败
# （grep 无匹配返回 1，在 pipefail 下会误杀脚本，故须吞掉）
for so in "$BUNDLE/lib/libstdc++.so.6" "$BUNDLE/lib/libgcc_s.so.1"; do
  M=$(objdump -T "$so" | { grep -oE 'GLIBC_[0-9.]+' || true; } | sed 's/^GLIBC_//' | sort -uV | tail -1)
  X=$(objdump -T "$so" | { grep -oE 'GLIBCXX_[0-9.]+' || true; } | sed 's/^GLIBCXX_//' | sort -uV | tail -1)
  echo "$(basename "$so"): 最高 GLIBC_${M:-none}（提供 GLIBCXX_${X:-none}）"
  if [ "$(printf '%s\n' "$MAX_GLIBC" "$M" | sort -V | tail -1)" != "$MAX_GLIBC" ]; then
    echo "✗ 随包库 $(basename "$so") 依赖 GLIBC_$M，超出 $MAX_GLIBC 上限" >&2; exit 1
  fi
done
echo "✓ 已内置 libstdc++ / libgcc_s 到 $BUNDLE/lib/"
