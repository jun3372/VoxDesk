#!/usr/bin/env bash
# 下载离线语音工作台所需的离线模型（FireRedAsr2 AED / Silero VAD / Pyannote / 3D-Speaker / 标点恢复）
# 用法: ./scripts/download_models.sh [目标目录]   （默认: ./models）
set -euo pipefail

DEST="${1:-models}"
mkdir -p "$DEST"
cd "$DEST"

BASE_RELEASE="https://github.com/k2-fsa/sherpa-onnx/releases/download"

download() {
  local url="$1" out="$2"
  if [ -f "$out" ]; then
    echo "已存在，跳过: $out"
    return 0
  fi
  echo "下载: $url"
  if command -v curl >/dev/null 2>&1; then
    curl -L --fail --retry 3 -o "$out.part" "$url"
  else
    wget -O "$out.part" "$url"
  fi
  mv "$out.part" "$out"
}

extract_tbz() {
  local archive="$1"
  echo "解压: $archive"
  tar xjf "$archive"
  rm -f "$archive"
}

echo "==> 1/4 FireRedAsr2 AED (中英文离线语音识别, int8, 约 1.2GB)"
download "$BASE_RELEASE/asr-models/sherpa-onnx-fire-red-asr2-zh_en-int8-2026-02-26.tar.bz2" \
  fire-red-asr2.tar.bz2
extract_tbz fire-red-asr2.tar.bz2

echo "==> 2/4 Silero VAD (语音活动检测, 约 2MB)"
download "$BASE_RELEASE/asr-models/silero_vad.onnx" silero_vad.onnx
echo "==> 3/4 说话人分离模型 (Pyannote 分割 + 3D-Speaker 嵌入, 约 52MB)"
download "$BASE_RELEASE/speaker-segmentation-models/sherpa-onnx-pyannote-segmentation-3-0.tar.bz2" \
  pyannote.tar.bz2
extract_tbz pyannote.tar.bz2
# 注意: 该 release tag 名称原文即带拼写错误 (recongition)，需原样使用
download "$BASE_RELEASE/speaker-recongition-models/3dspeaker_speech_eres2net_base_sv_zh-cn_3dspeaker_16k.onnx" \
  3dspeaker_speech_eres2net_base_sv_zh-cn_3dspeaker_16k.onnx

echo "==> 4/4 标点恢复模型 (可选, CT-Transformer 中英文, 约 290MB)"
if download "$BASE_RELEASE/punctuation-models/sherpa-onnx-punct-ct-transformer-zh-en-vocab272727-2024-04-12.tar.bz2" \
  punct.tar.bz2; then
  extract_tbz punct.tar.bz2
else
  echo "警告: 标点模型下载失败（可选组件，不影响核心功能）"
fi

echo
echo "全部完成 ✓"
echo "目录结构:"
find . -maxdepth 2 -type d | sort
echo
echo "应用内操作：启动离线语音工作台 → 左下角「加载模型」→ 选择 → 选择本目录 ($PWD)"
