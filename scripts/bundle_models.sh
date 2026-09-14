#!/usr/bin/env bash
# 将 ./models 中引擎所需模型拷贝进应用 bundle（构建后由 Makefile 自动调用）。
#
# 用法: scripts/bundle_models.sh <bundle 根目录> [模型源目录，默认 ./models]
# 布局: macOS *.app → Contents/Resources/models
#       Linux/Windows bundle → <bundle>/data/models
#
# 运行时由 ModelManager.bundledDir() 按可执行文件位置自动发现，
# 应用启动即用内置模型，无需用户选择外部模型目录。
set -euo pipefail

DEST_ROOT="${1:?用法: scripts/bundle_models.sh <bundle根目录> [模型源目录]}"
SRC="${2:-models}"

if [ ! -d "$SRC" ]; then
  echo "⚠ 未找到模型目录 $SRC —— 产物不含内置模型，运行时需手动选择模型目录" >&2
  echo "  （先执行 make models 下载模型后重新构建）" >&2
  exit 0
fi

case "$DEST_ROOT" in
  *.app) DEST="$DEST_ROOT/Contents/Resources/models" ;;
  *)     DEST="$DEST_ROOT/data/models" ;;
esac

rm -rf "$DEST"
mkdir -p "$DEST"

# 只拷引擎会加载的模型本体，排除原始下载包、示例音频与模型自带的测试音频。
# 另排除 macOS 的 AppleDouble/元数据文件（._* 与 .DS_Store）。
# 排除模式用裸名（不带 ./ 前缀）：macOS bsdtar 与 Linux GNU tar 均匹配任意层级
tar -C "$SRC" \
  --exclude='source' \
  --exclude='audio' \
  --exclude='test_wavs' \
  --exclude='.DS_Store' \
  --exclude='._*' \
  --exclude='*.tar.bz2' \
  --exclude='*.part' \
  -cf - . | tar -C "$DEST" -xf -

echo "✓ 内置模型已打包: $DEST ($(du -sh "$DEST" | cut -f1))"
