#!/usr/bin/env bash
# 从 Linux release bundle 生成 .deb 安装包（UOS 20 / Debian 系的原生安装格式）。
#
# 用法: scripts/build_deb.sh <bundle目录> <输出目录>
#   bundle 目录为 flutter build linux 的产物（含 UOS 兼容启动器的 bundle 根目录，
#   即 tar.gz 程序包里的 voxdesk/）；版本号取自 pubspec.yaml。
#   需在 Linux（CI 的 debian:buster 容器，或本地构建容器）内执行，依赖 dpkg-deb。
#
# 安装布局：
#   /opt/VoxDesk/                            程序本体（bundle 原样，含 voxdesk 启动器）
#   /usr/bin/voxdesk                         命令行入口（转发到 /opt/VoxDesk/voxdesk）
#   /usr/share/applications/voxdesk.desktop  桌面菜单项
#   /usr/share/icons/hicolor/512x512/apps/voxdesk.png
#
# 卸载（dpkg -r / apt remove）只清 /opt/VoxDesk 与上述入口文件；用户放进
# data/models/ 的模型属于「安装后新增内容」，不会被删除。

set -euo pipefail

usage() { echo "用法: $0 <bundle目录> <输出目录>" >&2; exit 1; }
[ $# -eq 2 ] || usage
BUNDLE=$(cd "$1" 2>/dev/null && pwd) || { echo "✗ bundle 目录不存在: $1" >&2; exit 1; }
OUT=$2
ROOT=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$OUT"

[ -x "$BUNDLE/voxdesk" ] || { echo "✗ $BUNDLE 不是有效的 bundle（缺 voxdesk 启动器）" >&2; exit 1; }

VER=$(sed -nE 's/^version:[[:space:]]*([0-9.]+).*/\1/p' "$ROOT/pubspec.yaml" | head -1)
VER=${VER:-0.0.0}
# deb 内部用标准架构名（amd64/arm64）；文件名沿用仓库的 x64/arm64 命名，与 tar.gz 配对
DEB_ARCH=$(dpkg --print-architecture)
case "$DEB_ARCH" in
  amd64) FILE_ARCH=x64 ;;
  arm64) FILE_ARCH=arm64 ;;
  *) echo "✗ 不支持的架构 $DEB_ARCH" >&2; exit 1 ;;
esac

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/DEBIAN" \
  "$STAGE/opt/VoxDesk" \
  "$STAGE/usr/bin" \
  "$STAGE/usr/share/applications" \
  "$STAGE/usr/share/icons/hicolor/512x512/apps"

cp -a "$BUNDLE/." "$STAGE/opt/VoxDesk/"

# 转发入口：exec 后 argv[0] 即 /opt/VoxDesk/voxdesk，launcher 内的
# cd "$(dirname "$0")" 仍解析到程序目录，不受 /usr/bin 调用影响
cat > "$STAGE/usr/bin/voxdesk" <<'EOF'
#!/bin/sh
exec /opt/VoxDesk/voxdesk "$@"
EOF
chmod 755 "$STAGE/usr/bin/voxdesk"

ICON="$ROOT/linux/assets/app_icon.png"
[ -f "$ICON" ] && cp "$ICON" "$STAGE/usr/share/icons/hicolor/512x512/apps/voxdesk.png"

cat > "$STAGE/usr/share/applications/voxdesk.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=离线语音工作台
Comment=完全离线的语音转写（FireRedAsr2 + 说话人分离）
Exec=/opt/VoxDesk/voxdesk
Icon=voxdesk
Terminal=false
Categories=AudioVideo;Audio;
StartupWMClass=com.example.voxdesk
EOF

# 运行库硬依赖只列各发行版稳定同名的 GTK/ALSA/Pulse；GStreamer 插件（音频解码
# 与回放必需）放 Recommends——包名在个别发行版有出入，缺了不应阻塞安装，
# 与 tar.gz 程序包「运行时依赖见说明」的口径一致
INSTALLED_KB=$(du -sk "$STAGE/opt" "$STAGE/usr" | awk '{s+=$1} END {print s}')
cat > "$STAGE/DEBIAN/control" <<EOF
Package: voxdesk
Version: $VER
Architecture: $DEB_ARCH
Maintainer: jun <main@jun3.work>
Installed-Size: $INSTALLED_KB
Depends: libgtk-3-0, liblzma5, libasound2, libpulse0
Recommends: gstreamer1.0-plugins-base, gstreamer1.0-plugins-good, gstreamer1.0-libav
Section: sound
Priority: optional
Description: 离线语音工作台（VoxDesk）
 完全离线的桌面语音转写应用：FireRedAsr2 中英文识别、Silero VAD、
 Pyannote + 3D-Speaker 说话人分离，数据不出本机。
 程序安装于 /opt/VoxDesk，运行依赖 GTK3 / GStreamer / PulseAudio / ALSA。
EOF

DEB="$OUT/voxdesk-linux-${FILE_ARCH}-v$VER.deb"
# --root-owner-group: 包内文件属主记为 root，而非执行打包的用户
dpkg-deb --root-owner-group --build "$STAGE" "$DEB" > /dev/null
echo "✓ 已生成 $DEB"
du -sh "$DEB"
