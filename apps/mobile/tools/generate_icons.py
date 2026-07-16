"""App icon generator — draws the brand mark (violet rounded square,
white shop awning + receipt, violet checkmark) and emits every platform
size: Android mipmaps + adaptive layers, iOS AppIcon set, Windows .ico,
and the in-app splash/brand asset.

Run from apps/mobile:  python3 tools/generate_icons.py
Regenerate anytime; output is deterministic.
"""
import json
import math
import os

import numpy as np
from PIL import Image, ImageDraw

SS = 2  # supersampling factor
BASE = 1024
W = BASE * SS

VIOLET_LIGHT = (139, 92, 246)   # #8B5CF6
VIOLET = (124, 58, 237)         # #7C3AED
VIOLET_DEEP = (109, 40, 217)    # #6D28D9
WHITE = (255, 255, 255, 255)


def gradient_bg(size, rounded=True, radius_frac=0.225):
    """Rounded square with a soft radial gradient (light top-left glow)."""
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float64) / size
    # radial distance from a glow point at (0.38, 0.30)
    d = np.sqrt((xx - 0.38) ** 2 + (yy - 0.30) ** 2)
    t = np.clip(d / 0.85, 0, 1) ** 1.15
    arr = np.zeros((size, size, 4), dtype=np.uint8)
    for i in range(3):
        arr[..., i] = (VIOLET_LIGHT[i] * (1 - t) + VIOLET_DEEP[i] * t).astype(np.uint8)
    arr[..., 3] = 255
    img = Image.fromarray(arr, 'RGBA')
    if rounded:
        mask = Image.new('L', (size, size), 0)
        ImageDraw.Draw(mask).rounded_rectangle(
            [0, 0, size - 1, size - 1], radius=int(size * radius_frac), fill=255)
        img.putalpha(mask)
    return img


def draw_glyph(size, scale=1.0, fg=WHITE, check=VIOLET_DEEP + (255,)):
    """The mark: shop awning (trapezoid + 3 hanging scallops) over a
    receipt with a shallow zigzag bottom and a bold checkmark."""
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    u = size / 1024.0 * scale
    c = size / 2

    def s(x, y):
        return (c + (x - 512) * u, c + (y - 512) * u)

    # ---- receipt (behind the awning) ----
    rx0, rx1 = 332, 692
    rtop, rbot = 430, 900
    tooth_d = 44
    teeth = 3
    pts = [s(rx0, rtop), s(rx1, rtop), s(rx1, rbot - tooth_d)]
    xs = np.linspace(rx1, rx0, teeth * 2 + 1)
    for i, xv in enumerate(xs[1:], 1):
        yv = rbot if i % 2 == 1 else rbot - tooth_d
        pts.append(s(xv, yv))
    d.polygon(pts, fill=fg)

    # ---- awning: trapezoid + 3 tangent scallops below its bottom edge ----
    a_top, a_bot = 300, 444
    ax0t, ax1t = 512 - 220, 512 + 220   # top width 440
    ax0b, ax1b = 512 - 300, 512 + 300   # bottom width 600
    d.polygon([s(ax0t, a_top), s(ax1t, a_top), s(ax1b, a_bot), s(ax0b, a_bot)], fill=fg)
    r = 100  # 3 tangent half-circle scallops along the bottom edge
    for cx_s in (ax0b + 100, 512, ax1b - 100):
        d.pieslice([s(cx_s - r, a_bot - r), s(cx_s + r, a_bot + r)], 0, 180, fill=fg)


    # ---- checkmark ----
    stroke = 58
    p1, p2, p3 = (420, 695), (502, 780), (652, 598)
    for a, b in [(p1, p2), (p2, p3)]:
        d.line([s(*a), s(*b)], fill=check, width=int(stroke * u))
    for x_, y_ in (p1, p2, p3):
        rr = stroke * u / 2
        xx_, yy_ = s(x_, y_)
        d.ellipse([xx_ - rr, yy_ - rr, xx_ + rr, yy_ + rr], fill=check)
    return img


_MASTER = {}


def master(kind):
    """Cache the expensive supersampled renders — one per kind."""
    if kind not in _MASTER:
        if kind == 'full':
            bg = gradient_bg(W)
            bg.alpha_composite(master('glyph'))
            _MASTER[kind] = bg
        elif kind == 'square':
            bg = gradient_bg(W, rounded=False)
            bg.alpha_composite(master('glyph'))
            _MASTER[kind] = bg
        elif kind == 'glyph':
            _MASTER[kind] = draw_glyph(W)
        elif kind == 'adaptive_fg':
            fgc = Image.new('RGBA', (W, W), (0, 0, 0, 0))
            fgc.alpha_composite(draw_glyph(int(W * 0.60)), (int(W * 0.20), int(W * 0.20)))
            _MASTER[kind] = fgc
    return _MASTER[kind]


def compose(size):
    return master('full').resize((size, size), Image.LANCZOS)


def load_source(root):
    """If assets/brand/icon_source.png exists (the original artwork),
    derive everything from it instead of the drawn recreation."""
    p = os.path.join(root, 'assets', 'brand', 'icon_source.png')
    if not os.path.exists(p):
        return False
    img = Image.open(p).convert('RGBA').resize((W, W), Image.LANCZOS)
    _MASTER['full'] = img
    _MASTER['square'] = img  # corners get masked by iOS anyway
    # glyph = near-white pixels (the mark) kept, everything else cleared
    arr = np.array(img)
    white = (arr[..., :3].astype(int).sum(axis=2) > 3 * 225) & (arr[..., 3] > 200)
    glyph = np.zeros_like(arr)
    glyph[white] = [255, 255, 255, 255]
    _MASTER['glyph'] = Image.fromarray(glyph, 'RGBA')
    fgc = Image.new('RGBA', (W, W), (0, 0, 0, 0))
    fgc.alpha_composite(_MASTER['glyph'].resize((int(W * 0.60),) * 2, Image.LANCZOS),
                        (int(W * 0.20), int(W * 0.20)))
    _MASTER['adaptive_fg'] = fgc
    return True


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    if load_source(root):
        print('using assets/brand/icon_source.png as artwork source')
    full = compose(1024)
    os.makedirs(os.path.join(root, 'assets', 'brand'), exist_ok=True)
    full.save(os.path.join(root, 'assets', 'brand', 'icon_1024.png'))

    # glyph-only (white mark, transparent bg) for splash/adaptive layers
    master('glyph').resize((1024, 1024), Image.LANCZOS).save(
        os.path.join(root, 'assets', 'brand', 'glyph_1024.png'))

    # ---- Android legacy mipmaps ----
    for folder, px in [('mipmap-mdpi', 48), ('mipmap-hdpi', 72), ('mipmap-xhdpi', 96),
                       ('mipmap-xxhdpi', 144), ('mipmap-xxxhdpi', 192)]:
        p = os.path.join(root, 'android', 'app', 'src', 'main', 'res', folder)
        os.makedirs(p, exist_ok=True)
        compose(px).save(os.path.join(p, 'ic_launcher.png'))

    # ---- Android adaptive: background color + padded glyph foreground ----
    res = os.path.join(root, 'android', 'app', 'src', 'main', 'res')
    for folder, px in [('mipmap-mdpi', 108), ('mipmap-hdpi', 162), ('mipmap-xhdpi', 216),
                       ('mipmap-xxhdpi', 324), ('mipmap-xxxhdpi', 432)]:
        master('adaptive_fg').resize((px, px), Image.LANCZOS).save(
            os.path.join(res, folder, 'ic_launcher_foreground.png'))
    os.makedirs(os.path.join(res, 'mipmap-anydpi-v26'), exist_ok=True)
    with open(os.path.join(res, 'mipmap-anydpi-v26', 'ic_launcher.xml'), 'w') as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n'
                '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
                '    <background android:drawable="@color/ic_launcher_background"/>\n'
                '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
                '</adaptive-icon>\n')
    vals = os.path.join(res, 'values')
    with open(os.path.join(vals, 'ic_launcher_background.xml'), 'w') as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
                '    <color name="ic_launcher_background">#7C3AED</color>\n</resources>\n')

    # ---- iOS ----
    setdir = os.path.join(root, 'ios', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset')
    meta = json.load(open(os.path.join(setdir, 'Contents.json')))
    for im in meta['images']:
        wpt = float(im['size'].split('x')[0])
        scale = int(im['scale'].replace('x', ''))
        px = int(round(wpt * scale))
        # iOS masks its own corners: give it the square (no transparency)
        master('square').convert('RGB').resize((px, px), Image.LANCZOS).save(
            os.path.join(setdir, im['filename']))

    # ---- Windows .ico ----
    ico_src = compose(256)
    ico_src.save(os.path.join(root, 'windows', 'runner', 'resources', 'app_icon.ico'),
                 sizes=[(256, 256), (128, 128), (64, 64), (48, 48), (32, 32), (16, 16)])

    print('all icons generated')


if __name__ == '__main__':
    main()
