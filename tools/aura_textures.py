#!/usr/bin/env python3
"""Render the weapon-aura magic circle layers (DDTank profile style) in four colours.

Writes assets/effects/aura/<cor>_<layer>.png (256x256, drawn at 4x and downsampled):
  disc  - glowing coloured disc with a soft outer halo (static, pulses)
  rays  - soft light rays (turn slowly)
  ring  - double outer ring with runes and dots (turns one way)
  star  - hexagram, inner circles and nodes (turns the other way)
Lines get a blurred coloured glow under a bright core, so the circle reads as light.

Usage: python tools/aura_textures.py   (needs Pillow + numpy)
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "effects", "aura")
SIZE = 256
SS = 4
BIG = SIZE * SS
C = BIG / 2
COLORS = {
    "verde": (60, 255, 106),
    "azul": (58, 155, 255),
    "roxa": (178, 92, 255),
    "vermelha": (255, 48, 48),
}


def mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def polar(r, angle):
    return (C + math.cos(angle) * r * SS, C + math.sin(angle) * r * SS)


def canvas():
    return Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))


def circle(draw, r, width, color):
    box = [C - r * SS, C - r * SS, C + r * SS, C + r * SS]
    draw.ellipse(box, outline=color, width=int(width * SS))


def glowing(lines, color, light, blur=5, strength=1.0):
    """Put a blurred coloured copy under the bright line art."""
    alpha = np.array(lines.split()[3]).astype(np.float32)
    glow_alpha = Image.fromarray(np.clip(alpha, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(blur * SS))
    glow = Image.new("RGBA", lines.size, color + (0,))
    glow.putalpha(glow_alpha.point(lambda v: min(255, int(v * 2.2 * strength))))
    core = Image.new("RGBA", lines.size, light + (0,))
    core.putalpha(lines.split()[3])
    return Image.alpha_composite(glow, core)


def finish(img, name):
    img.resize((SIZE, SIZE), Image.LANCZOS).save(os.path.join(OUT, name))


def glyph(draw, center, angle, kind, size, color):
    # Little runes made of strokes, rotated to follow the ring.
    strokes = [
        [(-1, -1), (1, -1), (0, -1), (0, 1)],
        [(-1, 1), (0, -1), (1, 1), (-0.6, 0.2), (0.6, 0.2)],
        [(-1, -1), (-1, 1), (1, 1), (1, -1)],
        [(-1, 0), (1, 0), (0, 0), (0, -1), (0, 1)],
        [(-1, -1), (1, 1), (0, 0), (1, -1)],
        [(-1, 1), (-1, -1), (1, 0), (-1, 1)],
    ][kind % 6]
    points = []
    cos, sin = math.cos(angle), math.sin(angle)
    for x, y in strokes:
        px = center[0] + (x * cos - y * sin) * size * SS
        py = center[1] + (x * sin + y * cos) * size * SS
        points.append((px, py))
    draw.line(points, fill=color, width=int(1.6 * SS), joint="curve")


def disc(base):
    dark = mix(base, (0, 0, 0), 0.62)
    mid = mix(base, (0, 0, 0), 0.3)
    light = mix(base, (255, 255, 255), 0.55)
    yy, xx = np.mgrid[0:BIG, 0:BIG]
    r = np.hypot(xx - C, yy - C) / (112 * SS)
    img = np.zeros((BIG, BIG, 4), np.float32)
    inside = r <= 1.0
    t = np.clip(r, 0, 1)
    for i in range(3):
        img[..., i] = mid[i] + (dark[i] - mid[i]) * t ** 1.4
        # Bright core glow in the middle.
        img[..., i] += (light[i] - img[..., i]) * np.clip(1 - r / 0.55, 0, 1) ** 2 * 0.55
    img[..., 3] = np.where(inside, 150 + 85 * t ** 2.5, 0)
    halo = (r > 1.0) & (r < 1.2)
    fade = np.clip(1 - (r - 1.0) / 0.2, 0, 1) ** 2
    for i in range(3):
        img[..., i] = np.where(halo, base[i], img[..., i])
    img[..., 3] = np.where(halo, 200 * fade, img[..., 3])
    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGBA")


def rays(base):
    light = mix(base, (255, 255, 255), 0.6)
    lines = canvas()
    draw = ImageDraw.Draw(lines)
    for i in range(12):
        angle = i * math.tau / 12
        tip = polar(116, angle)
        left = polar(26, angle - 0.16)
        right = polar(26, angle + 0.16)
        draw.polygon([left, tip, right], fill=light + (70,))
    return lines.filter(ImageFilter.GaussianBlur(3 * SS))


def ring(base):
    light = mix(base, (255, 255, 255), 0.72)
    lines = canvas()
    draw = ImageDraw.Draw(lines)
    circle(draw, 119, 2.4, light + (255,))
    circle(draw, 104, 1.6, light + (255,))
    circle(draw, 100, 0.9, light + (200,))
    for i in range(24):
        angle = i * math.tau / 24 + math.tau / 48
        glyph(draw, polar(111.5, angle), angle + math.pi / 2, i * 7 + i // 3, 4.2, light + (255,))
    for i in range(48):
        angle = i * math.tau / 48
        x, y = polar(125, angle)
        rad = (1.6 if i % 2 == 0 else 1.0) * SS
        draw.ellipse([x - rad, y - rad, x + rad, y + rad], fill=light + (255,))
    return glowing(lines, base, light, blur=4)


def star(base):
    light = mix(base, (255, 255, 255), 0.72)
    lines = canvas()
    draw = ImageDraw.Draw(lines)
    for turn in (0, math.pi):
        points = [polar(92, -math.pi / 2 + turn + k * math.tau / 3) for k in range(3)]
        draw.line(points + [points[0]], fill=light + (255,), width=int(2.2 * SS), joint="curve")
    circle(draw, 92, 1.4, light + (230,))
    circle(draw, 53, 2.0, light + (255,))
    circle(draw, 47, 1.0, light + (200,))
    hexagon = [polar(53, -math.pi / 2 + k * math.tau / 6) for k in range(6)]
    draw.line(hexagon + [hexagon[0]], fill=light + (220,), width=int(1.2 * SS))
    for k in range(6):
        x, y = polar(92, -math.pi / 2 + k * math.tau / 6)
        draw.ellipse([x - 6 * SS, y - 6 * SS, x + 6 * SS, y + 6 * SS], outline=light + (255,), width=int(1.6 * SS))
        draw.ellipse([x - 2.2 * SS, y - 2.2 * SS, x + 2.2 * SS, y + 2.2 * SS], fill=light + (255,))
    circle(draw, 16, 2.0, light + (255,))
    draw.ellipse([C - 7 * SS, C - 7 * SS, C + 7 * SS, C + 7 * SS], fill=light + (255,))
    return glowing(lines, base, light, blur=5)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for name, base in COLORS.items():
        finish(disc(base), f"{name}_disc.png")
        finish(rays(base), f"{name}_rays.png")
        finish(ring(base), f"{name}_ring.png")
        finish(star(base), f"{name}_star.png")
        print(name)
