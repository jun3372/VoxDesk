# 下载离线语音工作台所需的离线模型（Windows PowerShell）
# 用法: .\scripts\download_models.ps1 [目标目录]   （默认: .\models）
param(
    [string]$Dest = "models"
)

$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force -Path $Dest | Out-Null
# 后续下载/解压都以相对路径写入，必须先切进目标目录（与 download_models.sh 的 cd 对应）
Set-Location $Dest

$BaseRelease = "https://github.com/k2-fsa/sherpa-onnx/releases/download"

function Download {
    param([string]$Url, [string]$Out)
    if (Test-Path $Out) {
        Write-Host "已存在，跳过: $Out"
        return
    }
    Write-Host "下载: $Url"
    # 使用临时文件 + 移动，保证中断后不会留下半成品
    Invoke-WebRequest -Uri $Url -OutFile "$Out.part"
    Move-Item "$Out.part" $Out
}

function ExtractTbz {
    param([string]$Archive)
    Write-Host "解压: $Archive"
    tar xjf $Archive
    Remove-Item $Archive
}

Write-Host "==> 1/4 FireRedAsr2 AED (中英文离线语音识别, int8, 约 1.2GB)"
Download "$BaseRelease/asr-models/sherpa-onnx-fire-red-asr2-zh_en-int8-2026-02-26.tar.bz2" "fire-red-asr2.tar.bz2"
ExtractTbz "fire-red-asr2.tar.bz2"

Write-Host "==> 2/4 Silero VAD (语音活动检测, 约 2MB)"
Download "$BaseRelease/asr-models/silero_vad.onnx" "silero_vad.onnx"

Write-Host "==> 3/4 说话人分离模型 (Pyannote 分割 + 3D-Speaker 嵌入, 约 52MB)"
Download "$BaseRelease/speaker-segmentation-models/sherpa-onnx-pyannote-segmentation-3-0.tar.bz2" "pyannote.tar.bz2"
ExtractTbz "pyannote.tar.bz2"
# 注意: 该 release tag 名称原文即带拼写错误 (recongition)，需原样使用
Download "$BaseRelease/speaker-recongition-models/3dspeaker_speech_eres2net_base_sv_zh-cn_3dspeaker_16k.onnx" "3dspeaker_speech_eres2net_base_sv_zh-cn_3dspeaker_16k.onnx"

Write-Host "==> 4/4 标点恢复模型 (可选, CT-Transformer 中英文, 约 290MB)"
try {
    Download "$BaseRelease/punctuation-models/sherpa-onnx-punct-ct-transformer-zh-en-vocab272727-2024-04-12.tar.bz2" "punct.tar.bz2"
    ExtractTbz "punct.tar.bz2"
} catch {
    Write-Host "警告: 标点模型下载失败（可选组件，不影响核心功能）"
}

Write-Host ""
Write-Host "全部完成 ✓"
Write-Host "应用内操作：启动离线语音工作台 → 左下角「加载模型」→ 选择 → 选择本目录 ($((Get-Location).Path))"
