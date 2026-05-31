#!/usr/bin/env python3
"""Генерация иконок приложения qBitController (BitTorrent + загрузка).

Дизайн: тёмный графитово-синий градиент, лаконичная стрелка загрузки с «лотком»,
заливка cyan→blue, мягкое свечение. Мастер рендерится с суперсэмплингом и
уменьшается до всех нужных для iOS размеров.
"""
from PIL import Image, ImageDraw, ImageFilter
import os

OUT = os.path.join(os.path.dirname(__file__),
                   "qBitController/Assets.xcassets/AppIcon.appiconset")
R = 2048  # рабочее разрешение (суперсэмплинг для гладких краёв)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def vertical_gradient(size, top, bottom):
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        c = lerp(top, bottom, y / (size - 1))
        for x in range(size):
            px[x, y] = c
    return img


def build_master():
    # Фон — диагональный графитово-синий градиент.
    bg = vertical_gradient(R, (0x14, 0x1E, 0x33), (0x0B, 0x12, 0x20))

    # Мягкое радиальное свечение за глифом.
    glow = Image.new("L", (R, R), 0)
    gd = ImageDraw.Draw(glow)
    cx = cy = R // 2
    gd.ellipse([cx - R * 0.34, cy - R * 0.34, cx + R * 0.34, cy + R * 0.34], fill=120)
    glow = glow.filter(ImageFilter.GaussianBlur(R * 0.10))
    glow_layer = Image.new("RGB", (R, R), (0x2E, 0x6B, 0xFF))
    bg = Image.composite(glow_layer, bg, glow)

    # --- Маска глифа: стрелка загрузки + лоток ---
    mask = Image.new("L", (R, R), 0)
    d = ImageDraw.Draw(mask)
    cx = R // 2

    # Стебель стрелки (скруглённый прямоугольник).
    stem_w = int(R * 0.135)
    stem_top = int(R * 0.235)
    stem_bot = int(R * 0.555)
    d.rounded_rectangle([cx - stem_w // 2, stem_top, cx + stem_w // 2, stem_bot],
                        radius=stem_w // 2, fill=255)

    # Наконечник стрелки (треугольник, направлен вниз).
    head_half = int(R * 0.205)
    head_top = int(R * 0.505)
    head_tip = int(R * 0.730)
    d.polygon([(cx - head_half, head_top),
               (cx + head_half, head_top),
               (cx, head_tip)], fill=255)

    # «Лоток» загрузки снизу — U-образная подставка.
    tray_half = int(R * 0.235)
    tray_y = int(R * 0.800)
    tray_th = int(R * 0.050)
    riser_h = int(R * 0.085)
    # горизонтальная планка
    d.rounded_rectangle([cx - tray_half, tray_y,
                         cx + tray_half, tray_y + tray_th],
                        radius=tray_th // 2, fill=255)
    # левый и правый бортики
    d.rounded_rectangle([cx - tray_half, tray_y - riser_h,
                         cx - tray_half + tray_th, tray_y + tray_th],
                        radius=tray_th // 2, fill=255)
    d.rounded_rectangle([cx + tray_half - tray_th, tray_y - riser_h,
                         cx + tray_half, tray_y + tray_th],
                        radius=tray_th // 2, fill=255)

    # Заливка глифа вертикальным градиентом cyan → blue.
    glyph_grad = vertical_gradient(R, (0x4F, 0xF3, 0xD6), (0x2A, 0x7B, 0xFF))
    master = bg.convert("RGB")
    master.paste(glyph_grad, (0, 0), mask)

    return master.resize((1024, 1024), Image.LANCZOS)


def main():
    master = build_master()
    sizes = [1024, 180, 167, 152, 120, 87, 80, 60, 58, 40, 29, 20]
    for s in sizes:
        img = master if s == 1024 else master.resize((s, s), Image.LANCZOS)
        img.save(os.path.join(OUT, f"{s}.png"))
        print(f"  {s}x{s} -> {s}.png")
    print("Готово.")


if __name__ == "__main__":
    main()
