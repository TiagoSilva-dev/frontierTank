#!/usr/bin/env python3
"""Pixel art for the Founder Pack (Paladino do Sol), drawn pixel by pixel.

Everything that is geometry (halo, mandala, sigils, aura circle, footsteps, projectile,
explosion frames, badge, frame) is rendered here on a fixed palette instead of asking an
image model: rotation steps stay exact (no sub-pixel blur), shapes stay symmetric and
the result is reproducible. Characters, the weapon, the wings, the pet and the emote head
come from PixelLab (docs/PIXELLAB_FOUNDER.md).

    python tools/founder_art.py [halo|mandala|sigil|aura|foot|proj|boom|badge|frame|all]

Output goes to assets/founder/ (see docs/FOUNDER_PACK.md, section "Sprite sheets").
Needs Pillow and numpy.
"""
import math
import os
import sys

import numpy as np
from PIL import Image

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "founder")

# ---- palette: one ramp per material (dark -> light), shared outline -----------------------
GOLD = ["7a4a12", "b9791c", "f0a62c", "ffd25a", "fff0a8"]
WHITE = ["8e93b8", "c4c8e4", "e8ebfa", "ffffff"]
BLUE = ["16206e", "2a3fc0", "4a78ff", "9ad0ff"]
SUN = ["c8300f", "ff6a1a", "ffb02e", "fff26a"]
INK = "2a1c30"


def rgb(hex_color: str, alpha: int = 255):
    return (int(hex_color[0:2], 16), int(hex_color[2:4], 16), int(hex_color[4:6], 16), alpha)


class Canvas:
    """RGBA pixel grid with polar helpers. Shapes are decided per pixel centre (no AA)."""

    def __init__(self, size: int, height: int = 0, squash: float = 1.0, cy: float = -1.0):
        """`squash` < 1 draws a circle seen at a slant (an ellipse, as a decal on the ground);
        `cy` is the pixel row of the centre (default: the middle)."""
        self.w = size
        self.h = height or size
        self.px = np.zeros((self.h, self.w, 4), dtype=np.uint8)
        ys, xs = np.mgrid[0:self.h, 0:self.w]
        self.x = xs + 0.5 - self.w / 2.0
        self.y = (ys + 0.5 - (self.h / 2.0 if cy < 0 else cy)) / squash
        self.r = np.hypot(self.x, self.y)
        self.a = np.arctan2(self.y, self.x)

    def paint(self, mask, color):
        self.px[mask] = rgb(color) if isinstance(color, str) else color

    def outline(self, color: str = INK, diagonal: bool = False):
        """One pixel of outline around everything painted so far (under it, on empty pixels)."""
        solid = self.px[..., 3] > 0
        grown = solid.copy()
        grown[1:, :] |= solid[:-1, :]
        grown[:-1, :] |= solid[1:, :]
        grown[:, 1:] |= solid[:, :-1]
        grown[:, :-1] |= solid[:, 1:]
        if diagonal:
            grown[1:, 1:] |= solid[:-1, :-1]
            grown[:-1, :-1] |= solid[1:, 1:]
            grown[1:, :-1] |= solid[:-1, 1:]
            grown[:-1, 1:] |= solid[1:, :-1]
        self.px[grown & ~solid] = rgb(color)

    def clean(self):
        """Drop pixels with no 4-neighbour (orphans left by thin shapes)."""
        solid = self.px[..., 3] > 0
        neighbours = np.zeros_like(solid, dtype=int)
        neighbours[1:, :] += solid[:-1, :]
        neighbours[:-1, :] += solid[1:, :]
        neighbours[:, 1:] += solid[:, :-1]
        neighbours[:, :-1] += solid[:, 1:]
        self.px[solid & (neighbours == 0)] = 0

    def image(self) -> Image.Image:
        return Image.fromarray(self.px, "RGBA")

    def save(self, name: str):
        path = os.path.join(OUT, name)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        self.image().save(path)


def ang_diff(a, b):
    return (a - b + math.pi) % (2 * math.pi) - math.pi


def ray_mask(c: Canvas, theta: float, r0: float, r1: float, base: float, sharp: float = 1.0):
    """A pointed ray from radius r0 to r1, `base` pixels wide at r0, narrowing to a point."""
    d = ang_diff(c.a, theta)
    along = c.r * np.cos(d)
    across = np.abs(c.r * np.sin(d))
    t = np.clip((along - r0) / max(r1 - r0, 1e-6), 0, 1)
    width = base * 0.5 * (1.0 - t ** sharp)
    return (along >= r0) & (along <= r1) & (across <= np.maximum(width, 0.0))


def disc(c: Canvas, cx: float, cy: float, rad: float):
    return np.hypot(c.x - cx, c.y - cy) <= rad


def diamond(c: Canvas, cx: float, cy: float, rx: float, ry: float, theta: float = 0.0):
    dx, dy = c.x - cx, c.y - cy
    u = dx * math.cos(theta) + dy * math.sin(theta)
    v = -dx * math.sin(theta) + dy * math.cos(theta)
    return np.abs(u) / rx + np.abs(v) / ry <= 1.0


def pol(theta: float, radius: float):
    return radius * math.cos(theta), radius * math.sin(theta)


# ---- shaded shapes --------------------------------------------------------------------------

def ray_shaded(c: Canvas, theta: float, r0: float, r1: float, base: float, tones, sharp: float = 1.0):
    """A faceted ray: dark body, lit half, bright spine. tones = (dark, lit, spine)."""
    d = ang_diff(c.a, theta)
    along = c.r * np.cos(d)
    across = c.r * np.sin(d)
    t = np.clip((along - r0) / max(r1 - r0, 1e-6), 0, 1)
    width = np.maximum(base * 0.5 * (1.0 - t ** sharp), 0.0)
    inside = (along >= r0) & (along <= r1) & (np.abs(across) <= width)
    c.paint(inside, tones[0])
    c.paint(inside & (across <= 0.0), tones[1])
    c.paint(inside & (np.abs(across) <= np.maximum(width * 0.28, 0.45)), tones[2])


def petal(c: Canvas, theta: float, r0: float, r1: float, width: float, tones):
    """A lens-shaped petal along a radius (wide in the middle, pointed at both ends)."""
    d = ang_diff(c.a, theta)
    along = c.r * np.cos(d)
    across = c.r * np.sin(d)
    t = np.clip((along - r0) / max(r1 - r0, 1e-6), 0, 1)
    half = width * 0.5 * np.sin(np.pi * t)
    inside = (along >= r0) & (along <= r1) & (np.abs(across) <= half)
    c.paint(inside, tones[0])
    c.paint(inside & (across <= 0.0), tones[1])
    c.paint(inside & (np.abs(across) <= np.maximum(half * 0.25, 0.45)), tones[2])


def lens(c: Canvas, ox: float, oy: float, theta: float, length: float, width: float, tones):
    """A leaf/feather from (ox, oy) outward along `theta`: pointed at both ends, lit on one side."""
    dx, dy = c.x - ox, c.y - oy
    along = dx * math.cos(theta) + dy * math.sin(theta)
    across = -dx * math.sin(theta) + dy * math.cos(theta)
    t = np.clip(along / length, 0, 1)
    half = width * 0.5 * np.sin(np.pi * t) ** 0.8
    inside = (along >= 0) & (along <= length) & (np.abs(across) <= half)
    c.paint(inside, tones[0])
    c.paint(inside & (across <= 0.0), tones[1])
    c.paint(inside & (np.abs(across) <= np.maximum(half * 0.22, 0.4)), tones[2])


def band(c: Canvas, r0: float, r1: float, tones):
    """A ring: dark outer edge, body, bright core (radii are in pixels)."""
    c.paint((c.r >= r0) & (c.r <= r1), tones[0])
    span = r1 - r0
    if span >= 3:
        c.paint((c.r >= r0 + span * 0.2) & (c.r <= r1 - span * 0.05), tones[1])
        c.paint((c.r >= r0 + span * 0.45) & (c.r <= r0 + span * 0.85), tones[2])


# ---- halo --------------------------------------------------------------------------------

def halo_frame(size: int, rot: float, power: float = 0.0) -> Canvas:
    """The Halo Solar: bright ring with 8 long + 8 short faceted rays, a thin blue ring with 8
    gems, 8 runes on a translucent golden disc. `rot` turns it (radians; the design repeats
    every 45 degrees). `power` (0..1) adds the mandala ring used in the POW phase."""
    c = Canvas(size)
    s = size / 128.0
    outer = 46 * s
    # rays
    for k in range(16):
        theta = rot + k * math.pi / 8
        long_ray = k % 2 == 0
        r1 = (63 if long_ray else 55) * s
        base = (13 if long_ray else 8) * s
        tones = (GOLD[1], GOLD[3], GOLD[4]) if long_ray else (GOLD[1], GOLD[2], GOLD[3])
        ray_shaded(c, theta, outer - 4 * s, r1, base, tones, 0.9)
    # main ring
    band(c, outer - 4.2 * s, outer + 0.8 * s, (GOLD[1], GOLD[3], GOLD[4]))
    # thin blue ring with gems, and runes between
    inner = 33 * s
    c.paint((c.r >= inner - 1.1 * s) & (c.r <= inner + 1.1 * s), BLUE[1])
    c.paint((c.r >= inner - 0.3 * s) & (c.r <= inner + 0.5 * s), BLUE[2])
    for k in range(8):
        theta = rot + k * math.pi / 4 + math.pi / 8
        gx, gy = pol(theta, (inner + outer - 4.2 * s) / 2 + 0.3)
        glyph(c, gx, gy, theta, s, k, GOLD[2], GOLD[1])
    for k in range(8):
        theta = rot + k * math.pi / 4
        gx, gy = pol(theta, inner)
        c.paint(diamond(c, gx, gy, 3.6 * s, 3.6 * s, theta), GOLD[1])
        c.paint(diamond(c, gx, gy, 2.6 * s, 2.6 * s, theta), BLUE[1])
        c.paint(diamond(c, gx, gy, 1.6 * s, 1.6 * s, theta), BLUE[2])
        c.paint(disc(c, gx - 0.6, gy - 0.6, 0.7 * s), BLUE[3])
    if power > 0:
        rr = 24 * s
        c.paint((c.r >= rr - 0.6 * s) & (c.r <= rr + 0.6 * s), GOLD[3])
        for k in range(8):
            theta = -rot * 1.5 + k * math.pi / 4
            gx, gy = pol(theta, rr)
            c.paint(disc(c, gx, gy, 1.7 * s), GOLD[4])
    c.clean()
    c.outline(INK)
    return c


def glyph(c: Canvas, cx: float, cy: float, theta: float, s: float, variant: int, col: str = GOLD[4], shade: str = ""):
    """Tiny rune in local coordinates (u along the ring, v outward)."""
    dx, dy = c.x - cx, c.y - cy
    u = dx * -math.sin(theta) + dy * math.cos(theta)
    v = dx * math.cos(theta) + dy * math.sin(theta)
    unit = 1.0 * s
    m = (np.abs(u) <= 0.6 * unit) & (np.abs(v) <= 3.0 * unit)
    m = m | ((np.abs(v) <= 0.6 * unit) & (np.abs(u) <= 2.4 * unit))
    if variant % 2 == 0:
        m = m | ((np.abs(np.abs(u) - 2.0 * unit) <= 0.6 * unit) & (np.abs(v - 1.6 * unit) <= 1.0 * unit))
    else:
        ring = np.hypot(u, v - 1.8 * unit)
        m = m | ((ring <= 1.4 * unit) & (ring >= 0.7 * unit))
    m = m & (c.r < 60 * s)
    if shade:
        c.paint(m, shade)
    c.paint(m & (u - v * 0.0 <= 0.3 * unit), col)


def build_halo():
    for i in range(8):
        halo_frame(128, i * (math.pi / 4) / 8).save("halo/halo_%02d.png" % i)
    for i in range(8):
        halo_frame(128, i * (math.pi / 4) / 8, 1.0).save("halo/halo_power_%02d.png" % i)
    g = Canvas(128)
    for k in range(8):
        g.paint(g.r <= 63 - k * 7.5, (255, 190, 70, 12 + k * 6))
    g.save("halo/glow.png")


# ---- mandala (POW) -----------------------------------------------------------------------

def mandala_frame(size: int, rot: float) -> Canvas:
    """Huge solar mandala: counter-rotating rings, 24 outer rays, 16 petals, 8-pointed star."""
    c = Canvas(size)
    s = size / 192.0
    # translucent royal-blue / gold disc so the sign reads over any scenery
    for rad, colour in ((80, (30, 40, 150, 92)), (62, (0, 0, 0, 0))):
        c.paint((c.r <= rad * s) & (c.r >= 60 * s), colour)
    # outer sun rays (24)
    for k in range(24):
        theta = rot * 0.5 + k * math.pi / 12
        long_ray = k % 2 == 0
        ray_shaded(c, theta, 78 * s, (95 if long_ray else 88) * s, (9 if long_ray else 6) * s, (GOLD[1], GOLD[3], GOLD[4]), 0.9)
    band(c, 73 * s, 80 * s, (GOLD[1], GOLD[3], GOLD[4]))
    # rune belt (turns one way)
    for k in range(16):
        theta = rot + k * math.pi / 8
        gx, gy = pol(theta, 67 * s)
        glyph(c, gx, gy, theta, s * 1.4, k, GOLD[4], GOLD[1])
    band(c, 57 * s, 60 * s, (GOLD[1], GOLD[2], GOLD[3]))
    # 16 petals (counter-rotating)
    for k in range(16):
        theta = -rot * 0.7 + k * math.pi / 8
        long_petal = k % 2 == 0
        petal(c, theta, 30 * s, (57 if long_petal else 50) * s, (15 if long_petal else 10) * s, (GOLD[1], GOLD[3], GOLD[4]))
    # blue gem belt
    for k in range(12):
        theta = -rot * 1.2 + k * math.pi / 6
        gx, gy = pol(theta, 44 * s)
        c.paint(diamond(c, gx, gy, 3.4 * s, 4.8 * s, theta), GOLD[1])
        c.paint(diamond(c, gx, gy, 2.4 * s, 3.6 * s, theta), BLUE[1])
        c.paint(diamond(c, gx, gy, 1.3 * s, 2.0 * s, theta), BLUE[3])
    band(c, 27 * s, 30 * s, (GOLD[1], GOLD[2], GOLD[4]))
    # core: 8-pointed star + sun disc
    for k in range(8):
        theta = rot * 1.5 + k * math.pi / 4
        ray_shaded(c, theta, 6 * s, 28 * s, 11 * s, (GOLD[1], GOLD[3], GOLD[4]), 1.0)
    c.paint(c.r <= 13 * s, GOLD[1])
    c.paint(c.r <= 11.5 * s, GOLD[3])
    c.paint(c.r <= 8.5 * s, SUN[2])
    c.paint(c.r <= 5.5 * s, SUN[3])
    c.paint(c.r <= 2.8 * s, "ffffff")
    c.clean()
    c.outline(INK)
    return c


def build_mandala():
    for i in range(12):
        mandala_frame(192, i * (math.pi / 12) / 12).save("mandala/mandala_%02d.png" % i)


# ---- ground sigil, aura circle, footsteps -------------------------------------------------

def sigil(c: Canvas, s: float, rot: float = 0.0, tones=None, blue: bool = True):
    """Sun sign drawn flat: ring, 8 rays, inner star. Works on squashed canvases (ground)."""
    tones = tones or (GOLD[1], GOLD[3], GOLD[4])
    band(c, 38 * s, 44 * s, tones)
    c.paint((c.r >= 30 * s) & (c.r <= 31.4 * s), GOLD[2])
    for k in range(8):
        theta = rot + k * math.pi / 4
        long_ray = k % 2 == 0
        ray_shaded(c, theta, 42 * s, (60 if long_ray else 52) * s, (10 if long_ray else 6) * s, tones, 0.9)
    for k in range(8):
        theta = rot + k * math.pi / 4 + math.pi / 8
        gx, gy = pol(theta, 34.5 * s)
        c.paint(disc(c, gx, gy, 1.4 * s), BLUE[2] if blue else GOLD[4])
    for k in range(4):
        theta = rot + k * math.pi / 2
        ray_shaded(c, theta, 4 * s, 28 * s, 9 * s, tones, 1.0)
    c.paint(c.r <= 6 * s, tones[0])
    c.paint(c.r <= 4.6 * s, SUN[2])
    c.paint(c.r <= 2.4 * s, SUN[3])


def build_sigil():
    c = Canvas(160, 64, squash=0.36, cy=32)
    sigil(c, 1.3)
    c.clean()
    c.outline(INK)
    c.save("sigil/sun_sigil.png")


def build_aura():
    for i in range(8):
        rot = i * (math.pi / 4) / 8
        c = Canvas(96, 40, squash=0.4, cy=20)
        s = 1.0
        band(c, 40 * s, 44 * s, (GOLD[1], GOLD[2], GOLD[3]))
        band(c, 27 * s, 29 * s, (GOLD[1], GOLD[2], GOLD[2]))
        for k in range(8):
            theta = rot + k * math.pi / 4
            gx, gy = pol(theta, 34 * s)
            c.paint(disc(c, gx, gy, 2.0 * s), GOLD[1])
            c.paint(disc(c, gx, gy, 1.2 * s), GOLD[4])
        for k in range(8):
            theta = -rot * 1.3 + k * math.pi / 4 + math.pi / 8
            ray_shaded(c, theta, 30 * s, 40 * s, 4.5 * s, (GOLD[1], GOLD[3], GOLD[4]), 0.9)
        c.clean()
        c.save("aura/aura_%02d.png" % i)
    # in battle: just a thin ring (35% opacity is applied by the engine)
    c = Canvas(96, 40, squash=0.4, cy=20)
    band(c, 41 * s, 44 * s, (GOLD[2], GOLD[3], GOLD[4]))
    c.save("aura/aura_thin.png")


def build_foot():
    # six frames of a 32x16 sun mark: surges, flares, settles (the engine fades the last ones)
    sizes = [0.35, 0.62, 0.85, 0.85, 0.78, 0.7]
    for i, k in enumerate(sizes):
        c = Canvas(32, 16, squash=0.5, cy=8)
        t = 0.36 * k * 2.0
        rot = i * math.pi / 12
        band(c, 11.5 * t / 0.36 * 0.36 * 2.0 * 0.5, 13.5 * t / 0.36 * 0.36 * 2.0 * 0.5, (GOLD[1], GOLD[3], GOLD[4]))
        for j in range(8):
            theta = rot + j * math.pi / 4
            ray_shaded(c, theta, 12 * k * 0.9, (18 if j % 2 == 0 else 15) * k, 3.0, (GOLD[1], GOLD[3], GOLD[4]), 1.0)
        c.paint(c.r <= 3.0 * k, SUN[2])
        c.paint(c.r <= 1.6 * k, "fff8d0")
        c.clean()
        c.save("foot/footstep_%02d.png" % i)


# ---- projectile, lance, feather ------------------------------------------------------------

def build_projectile():
    """Estrela do Amanhecer: sun orb with a 4-point star that turns (8 frames, 32x32)."""
    for i in range(8):
        rot = i * (math.pi / 2) / 8
        c = Canvas(32)
        for k in range(4):
            theta = rot + k * math.pi / 2
            ray_shaded(c, theta, 5, 15, 7, (GOLD[1], GOLD[3], GOLD[4]), 0.9)
        for k in range(4):
            theta = rot + math.pi / 4 + k * math.pi / 2
            ray_shaded(c, theta, 5, 11, 4, (GOLD[1], GOLD[2], GOLD[3]), 1.0)
        c.paint(c.r <= 7.6, GOLD[1])
        c.paint(c.r <= 6.6, SUN[1])
        c.paint(c.r <= 5.4, SUN[2])
        c.paint(c.r <= 3.8, SUN[3])
        c.paint(c.r <= 2.0, "ffffff")
        c.clean()
        c.outline(INK)
        c.save("projectile/frame_%02d.png" % i)


def build_lance():
    """Lança Celestial Solar, pointing right (4 shimmer frames, 128x40)."""
    for i in range(4):
        c = Canvas(128, 40)
        cy = 0.0
        # shaft: long tapering beam of light, core white
        for x0, half, col in ((-62, 5, GOLD[1]), (-60, 4, GOLD[2]), (-58, 3, GOLD[3]), (-56, 1.6, GOLD[4])):
            taper = np.clip((c.x - x0) / (40 - x0), 0, 1)
            m = (c.x >= x0) & (c.x <= 38) & (np.abs(c.y) <= half * (0.45 + 0.55 * taper))
            c.paint(m, col)
        # fletching: two swept feathers at the tail
        for sign in (-1, 1):
            lens(c, -44, 0, math.pi + sign * 0.62, 24, 9, (WHITE[0], WHITE[2], WHITE[3]))
            lens(c, -50, 0, math.pi + sign * 0.35, 16, 6, (GOLD[1], GOLD[3], GOLD[4]))
        # head: big sun diamond with a blue crystal
        head = diamond(c, 46, 0, 18, 10)
        c.paint(head, GOLD[1])
        c.paint(diamond(c, 47, 0, 15, 8), GOLD[3])
        c.paint(diamond(c, 48, 0, 10, 5.5), BLUE[1])
        c.paint(diamond(c, 49, -0.3, 6.5, 3.2), BLUE[3])
        c.paint(disc(c, 50, -1, 1.4), "ffffff")
        # orbiting rings (the engine adds more as the flight goes on)
        for j, rx in enumerate((12, 26)):
            ring = np.abs(np.hypot((c.x - rx) / 3.0, c.y / 15.0) - 1.0) <= 0.14
            c.paint(ring & (c.x < 40), GOLD[3] if (i + j) % 2 == 0 else GOLD[4])
        c.clean()
        c.outline(INK)
        c.save("lance/frame_%02d.png" % i)


def build_feather():
    c = Canvas(16, 40)
    for k in range(2):
        pass
    # curved quill with barbs, white with a blue-gold tip
    t = (c.y + 20) / 40.0
    curve = 2.5 * np.sin(t * np.pi)
    spine = np.abs(c.x - curve) <= 0.5
    half = 5.0 * np.sin(np.clip(t, 0, 1) * np.pi) ** 0.8
    vane = (np.abs(c.x - curve) <= half) & (t > 0.08) & (t < 0.97)
    c.paint(vane, WHITE[1])
    c.paint(vane & (c.x <= curve), WHITE[2])
    c.paint(vane & (np.abs(c.x - curve) <= half * 0.4), WHITE[3])
    c.paint(vane & (t > 0.72) & (np.abs(c.x - curve) <= half * 0.8), GOLD[3])
    c.paint(vane & (t > 0.86), GOLD[1])
    c.paint(spine & (t > 0.04), GOLD[2])
    c.clean()
    c.outline(INK)
    c.save("feather.png")


# ---- explosion ------------------------------------------------------------------------------

BOOM_W, BOOM_H, BOOM_GROUND = 192, 140, 120


def boom_frame(i: int) -> Canvas:
    """The explosion of the sun. Half the canvas width is the real damage radius R (96 px):
    nothing that can be read as an area is drawn beyond it. Ground line at row 120."""
    R = BOOM_W / 2
    c = Canvas(BOOM_W, BOOM_H, squash=1.0, cy=BOOM_GROUND)
    flat = Canvas(BOOM_W, BOOM_H, squash=0.3, cy=BOOM_GROUND)
    if i == 0:  # FRAME 1: small golden flash
        for k in range(8):
            ray_shaded(c, k * math.pi / 4, 2, (26 if k % 2 == 0 else 18), 9, (GOLD[2], GOLD[4], "ffffff"), 0.9)
        c.paint(c.r <= 10, GOLD[3])
        c.paint(c.r <= 6, "ffffff")
        c.px[c.y > 2] = 0
    elif i == 1:  # FRAME 2: sun sigil appears on the ground (0.8 R), flash fading
        sigil(flat, (0.8 * R) / 60.0 * 0.96)
        for k in range(8):
            ray_shaded(c, k * math.pi / 4, 2, (20 if k % 2 == 0 else 12), 7, (GOLD[2], GOLD[4], "ffffff"), 0.9)
        c.paint(c.r <= 6, "ffffff")
        c.px[c.y > 2] = 0
        merged = flat.px.copy()
        merged[(c.px[..., 3] > 0)] = c.px[(c.px[..., 3] > 0)]
        c.px = merged
    elif i == 2:  # FRAME 3: vertical explosion of light (narrow pillar, < 0.25 R wide)
        sigil(flat, (0.8 * R) / 60.0 * 0.96)
        c.px = flat.px.copy()
        width = 10.0
        top = 6
        y = np.arange(BOOM_H)[:, None] + 0.5
        xs = np.arange(BOOM_W)[None, :] + 0.5 - BOOM_W / 2
        ygrow = (BOOM_GROUND - y)
        body = (ygrow >= 0) & (y >= top) & (np.abs(xs) <= width * (0.55 + 0.45 * np.clip(ygrow / 40.0, 0, 1)) * (0.4 + 0.6 * np.clip((y - top) / 30.0, 0, 1)))
        c.paint(body, GOLD[2])
        c.paint(body & (np.abs(xs) <= width * 0.6), GOLD[3])
        c.paint(body & (np.abs(xs) <= width * 0.28), GOLD[4])
        c.paint(body & (np.abs(xs) <= width * 0.12), "ffffff")
        base = Canvas(BOOM_W, BOOM_H, squash=1.0, cy=BOOM_GROUND)
        base.paint((base.r <= 18) & (base.y <= 2), GOLD[3])
        base.paint((base.r <= 11) & (base.y <= 2), "ffffff")
        c.px[(base.px[..., 3] > 0)] = base.px[(base.px[..., 3] > 0)]
    elif i == 3:  # FRAME 4: energy ring expands to exactly R, pillar fading
        sigil(flat, (0.8 * R) / 60.0 * 0.96, tones=(GOLD[1], GOLD[2], GOLD[3]))
        c.px = flat.px.copy()
        ring = Canvas(BOOM_W, BOOM_H, squash=0.3, cy=BOOM_GROUND)
        band(ring, R - 7.0, R - 0.4, (GOLD[2], GOLD[3], GOLD[4]))
        c.px[(ring.px[..., 3] > 0)] = ring.px[(ring.px[..., 3] > 0)]
        width = 6.0
        y = np.arange(BOOM_H)[:, None] + 0.5
        xs = np.arange(BOOM_W)[None, :] + 0.5 - BOOM_W / 2
        body = ((BOOM_GROUND - y) >= 0) & (y >= 40) & (np.abs(xs) <= width * np.clip((y - 40) / 25.0, 0.2, 1))
        c.paint(body, GOLD[3])
        c.paint(body & (np.abs(xs) <= width * 0.4), GOLD[4])
    else:  # FRAME 5: small stars rise and go out; nothing wider than R
        flat.paint(np.abs(flat.r - 0.8 * R * 0.6) <= 0.8, (255, 214, 110, 90))
        c.px = flat.px.copy()
        rng = np.random.RandomState(7)
        for k in range(14):
            x = rng.uniform(-0.8 * R, 0.8 * R)
            y = BOOM_GROUND - rng.uniform(8, 88)
            star = diamond(Canvas(BOOM_W, BOOM_H, cy=BOOM_GROUND), x, y - BOOM_GROUND, 2.0, 2.0)
            c.px[star] = rgb(GOLD[4] if k % 3 else "ffffff", 255 if k % 2 else 200)
    c.clean()
    c.outline(INK)
    c.px[BOOM_GROUND + 1:, :] = 0
    return c


def build_boom():
    for i in range(5):
        boom_frame(i).save("explosion/frame_%02d.png" % i)


# ---- badge and frame --------------------------------------------------------------------------

def badge(size: int) -> Canvas:
    c = Canvas(size)
    s = size / 32.0
    c.paint(c.r <= 15 * s, GOLD[1])
    c.paint(c.r <= 13.6 * s, GOLD[3])
    c.paint(c.r <= 12.2 * s, BLUE[0])
    c.paint((c.r <= 11 * s) & (c.r >= 10.2 * s), BLUE[1])
    for k in range(8):
        theta = k * math.pi / 4
        ray_shaded(c, theta, 5 * s, (11.2 if k % 2 == 0 else 8.6) * s, (5.0 if k % 2 == 0 else 3.2) * s, (GOLD[1], GOLD[3], GOLD[4]), 0.9)
    c.paint(c.r <= 5.6 * s, GOLD[1])
    c.paint(c.r <= 4.6 * s, SUN[2])
    c.paint(c.r <= 3.0 * s, SUN[3])
    c.paint(c.r <= 1.4 * s, "ffffff")
    c.clean()
    c.outline(INK)
    return c


def build_badge():
    for size in (16, 24, 32, 64):
        badge(size).save("badge/badge_%d.png" % size)


def build_frame():
    """Portrait frame, 128x104: gold border (the frame itself is the central 88x88 square at
    rows 12..100), two feathered wings rising at the top corners, a sun above and a blue
    crystal below."""
    c = Canvas(128, 104, cy=56)
    box = (np.abs(c.x) <= 44) & (np.abs(c.y) <= 44)
    hollow = (np.abs(c.x) <= 38) & (np.abs(c.y) <= 38)
    # wings first, so the border sits over their roots
    for sx in (-1, 1):
        base_x, base_y = sx * 41, -36
        for k, (angle, length, width) in enumerate(((-0.30, 26, 9), (-0.62, 25, 9), (-0.95, 22, 8), (-1.28, 18, 7), (-1.55, 13, 6))):
            theta = angle if sx > 0 else math.pi - angle
            lens(c, base_x, base_y, theta, length, width, (WHITE[0], WHITE[2], WHITE[3]) if k % 2 == 0 else (WHITE[1], WHITE[2], WHITE[3]))
        # gold edge feathers on the leading side
        lens(c, base_x, base_y, (-1.75 if sx > 0 else math.pi + 1.75), 12, 5, (GOLD[1], GOLD[3], GOLD[4]))
    c.paint(box & ~hollow, GOLD[1])
    c.paint(box & ~((np.abs(c.x) <= 41) & (np.abs(c.y) <= 41)), GOLD[2])
    c.paint(box & ~((np.abs(c.x) <= 42.2) & (np.abs(c.y) <= 42.2)) & (c.y <= -c.x * 0.0), GOLD[3])
    c.paint(box & (np.abs(c.x) > 38) & (np.abs(c.x) < 40) & (c.y < 0), GOLD[3])
    c.paint(hollow & ~((np.abs(c.x) <= 36.4) & (np.abs(c.y) <= 36.4)), BLUE[1])
    c.paint(hollow & ~((np.abs(c.x) <= 37.4) & (np.abs(c.y) <= 37.4)), BLUE[2])
    c.paint(hollow & ((np.abs(c.x) > 37.4) | (np.abs(c.y) > 37.4)) & False, BLUE[3])
    for sx in (-1, 1):
        for sy in (-1, 1):
            c.paint(diamond(c, sx * 42, sy * 42, 5.5, 5.5), GOLD[1])
            c.paint(diamond(c, sx * 42, sy * 42, 4.0, 4.0), GOLD[3])
            c.paint(diamond(c, sx * 42, sy * 42, 2.2, 2.2), GOLD[4])
    # crown sun above, crystal below
    for k in range(7):
        angle = -math.pi / 2 + (k - 3) * 0.42
        lens(c, 0, -45, angle, 14 if k == 3 else 11, 4.5, (GOLD[1], GOLD[3], GOLD[4]))
    c.paint(disc(c, 0, -45, 6.5), GOLD[1])
    c.paint(disc(c, 0, -45, 5.2), SUN[2])
    c.paint(disc(c, 0, -45, 3.0), SUN[3])
    c.paint(diamond(c, 0, 44, 8.5, 6.5), GOLD[1])
    c.paint(diamond(c, 0, 44.5, 6.5, 5.0), BLUE[1])
    c.paint(diamond(c, 0, 44.5, 4.0, 3.2), BLUE[2])
    c.paint(diamond(c, -0.8, 43.5, 1.8, 1.6), BLUE[3])
    c.clean()
    c.outline(INK)
    c.save("frame/founder_frame.png")


# ---- emote ------------------------------------------------------------------------------------

def build_emote():
    """Paladino Approved: the Paladino's own head (from the skin's front view) with a
    confident smirk, a raised eyebrow and a star that twinkles. 6 frames, 64x64."""
    src = Image.open(os.path.join(OUT, "..", "characters", "roupa_paladino_sol", "south.png")).convert("RGBA").crop((37, 4, 101, 68))
    base = np.array(src)
    ink = rgb("3a1c1c")
    brow = rgb("7a4a12")
    for x, y in ((29, 50), (30, 50), (31, 50), (32, 50), (33, 49), (34, 48)):
        base[y, x] = ink
    for x, y in ((38, 35), (39, 34), (40, 34), (41, 34), (42, 35)):
        base[y, x] = brow
    for k in range(6):
        frame = np.zeros_like(base)
        bob = 1 if k in (2, 3) else 0
        frame[bob:, :] = base[: 64 - bob, :]
        c = Canvas(64)
        size = (2, 4, 6, 5, 3, 1)[k]
        cx, cy = 20.0, -21.0
        for j in range(4):
            theta = j * math.pi / 2
            ray_shaded(c, theta, 0, size, max(2.0, size * 0.55), ("ffd25a", "fff0a8", "ffffff"), 0.9)
        c.px[...] = np.roll(np.roll(c.px, int(cx), axis=1), int(cy), axis=0)
        c.px[c.px[..., 3] > 0] = c.px[c.px[..., 3] > 0]
        out = Image.fromarray(frame, "RGBA")
        out.alpha_composite(Image.fromarray(c.px, "RGBA"))
        path = os.path.join(OUT, "emote", "frame_%02d.png" % k)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        out.save(path)


# ---- driver -------------------------------------------------------------------------------

TARGETS = {"halo": build_halo, "mandala": build_mandala, "sigil": build_sigil, "aura": build_aura, "foot": build_foot,
           "proj": build_projectile, "lance": build_lance, "feather": build_feather, "boom": build_boom,
           "badge": build_badge, "frame": build_frame, "emote": build_emote}


def contact_sheet(paths, name, scale=3, cols=4, bg=(40, 44, 70, 255)):
    images = [Image.open(os.path.join(OUT, p)).convert("RGBA") for p in paths]
    w = max(i.width for i in images)
    h = max(i.height for i in images)
    rows = (len(images) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * w, rows * h), bg)
    for k, image in enumerate(images):
        sheet.alpha_composite(image, ((k % cols) * w + (w - image.width) // 2, (k // cols) * h + (h - image.height) // 2))
    sheet = sheet.resize((sheet.width * scale // 2, sheet.height * scale // 2), Image.NEAREST)
    sheet.save(os.path.join(OUT, name))


if __name__ == "__main__":
    wanted = sys.argv[1:] or ["all"]
    for key, fn in TARGETS.items():
        if "all" in wanted or key in wanted:
            fn()
