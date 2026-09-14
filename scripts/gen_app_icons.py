#!/usr/bin/env python3
"""生成全平台应用图标：与首页左上角 Logo 一致（品牌渐变圆角方块 + 白色 graphic_eq 均衡器图形）。

覆盖 macOS（Assets.xcassets）、Windows（.ico）、Linux（窗口图标 PNG）、
iOS / Android（启动器图标）。重新生成：python3 scripts/gen_app_icons.py
"""

import os
import re

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# 与 lib/core/theme.dart 的 AppColors 保持一致
GRAD_TOP = (0xE8, 0x5A, 0x55)    # primaryLight
GRAD_BOTTOM = (0xD9, 0x3A, 0x44)  # primaryDark

# 超采样倍数（先放大绘制再缩小，得到平滑边缘）
SS = 4


def _gradient(size, top=GRAD_TOP, bottom=GRAD_BOTTOM):
    grad = Image.new("RGB", (1, size))
    for y in range(size):
        t = y / (size - 1)
        grad.putpixel((0, y), tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return grad.resize((size, size))


def _draw_equalizer(img):
    """在整幅图上绘制 graphic_eq 圆头五柱（24 单位栅格，垂直居中）。"""
    d = ImageDraw.Draw(img)
    size = img.width
    unit = size * 0.56 / 24  # 图形占 56%，对齐 Logo 中 22/38 的占比
    bar_w = 2 * unit
    cx = cy = size / 2
    centers = [4, 8, 12, 16, 20]
    heights = [4, 12, 20, 12, 4]
    for c, h in zip(centers, heights):
        x = cx + (c - 12) * unit
        half = h / 2 * unit
        d.rounded_rectangle(
            [x - bar_w / 2, cy - half, x + bar_w / 2, cy + half],
            radius=bar_w / 2,
            fill=(255, 255, 255, 255),
        )


def make_master(rounded=True, size=1024):
    """rounded=True：Big Sur 风格圆角方块（四周留白）；False：满幅正方形（iOS/Android）。"""
    s = size * SS
    if rounded:
        inset = round(s * 0.0977)  # 1024 画布内 824 图形
        art = s - 2 * inset
        canvas = Image.new("RGBA", (s, s), (0, 0, 0, 0))
        mask = Image.new("L", (art, art), 0)
        ImageDraw.Draw(mask).rounded_rectangle(
            [0, 0, art - 1, art - 1], radius=round(art * 0.225), fill=255
        )
        canvas.paste(_gradient(art).convert("RGBA"), (inset, inset), mask)
        _draw_equalizer(canvas)
    else:
        canvas = _gradient(s).convert("RGBA")
        _draw_equalizer(canvas)
    return canvas.resize((size, size), Image.LANCZOS)


def write_png(master, path, size):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    master.resize((size, size), Image.LANCZOS).save(path)
    print(f"  {os.path.relpath(path, ROOT)} ({size}x{size})")


def gen_macos(master):
    out = os.path.join(ROOT, "macos/Runner/Assets.xcassets/AppIcon.appiconset")
    print("macOS:")
    for n in (16, 32, 64, 128, 256, 512, 1024):
        write_png(master, os.path.join(out, f"app_icon_{n}.png"), n)


def gen_windows(master):
    path = os.path.join(ROOT, "windows/runner/resources/app_icon.ico")
    src = master.resize((256, 256), Image.LANCZOS)
    src.save(
        path,
        format="ICO",
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )
    print(f"Windows:\n  {os.path.relpath(path, ROOT)} (16-256)")


def gen_linux(master):
    write_png(master, os.path.join(ROOT, "linux/assets/app_icon.png"), 512)


def gen_ios():
    out = os.path.join(ROOT, "ios/Runner/Assets.xcassets/AppIcon.appiconset")
    master = make_master(rounded=False)
    print("iOS:")
    for name in os.listdir(out):
        m = re.fullmatch(r"Icon-App-(\d+)x(\d+)@(\d+)x\.png", name)
        if not m:
            continue
        size = int(m.group(1)) * int(m.group(3))
        write_png(master, os.path.join(out, name), size)


def gen_android(master):
    print("Android:")
    for dpi, size in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)):
        write_png(
            master,
            os.path.join(ROOT, f"android/app/src/main/res/mipmap-{dpi}/ic_launcher.png"),
            size,
        )


def main():
    rounded = make_master(rounded=True)
    square = make_master(rounded=False)
    gen_macos(rounded)
    gen_windows(rounded)
    gen_linux(rounded)
    gen_ios()
    gen_android(square)
    print("完成。")


if __name__ == "__main__":
    main()
