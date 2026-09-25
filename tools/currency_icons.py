#!/usr/bin/env python3
"""Draw the 0.10 currency icons (32x32 pixel art) into assets/items/currency/.

Brasa (ember), Coroa (crown), Estrela (star), Tormenta (storm orb), Solar (sun),
Eclipse and Espelho Celeste (sky mirror). Shapes are shaded with a light from the top
left, mapped onto small colour ramps and outlined with the interface ink, so they sit
next to the PixelLab stones and coin. They stand in until PixelLab icons are generated
(docs/PIXELLAB_0_10.md has the prompts); a PNG with the same name replaces them.

Usage: python tools/currency_icons.py [--preview out.png]
"""
import math
import os
import sys

import numpy as np
from PIL import Image

W = 32
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "items", "currency")
INK = (26, 12, 6)
LIGHT = np.array([-0.45, -0.62, 0.64])
LIGHT = LIGHT / np.linalg.norm(LIGHT)


def hexc(value):
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def ramp(*colors):
    return [hexc(c) for c in colors]


class Canvas:
    def __init__(self):
        self.px = np.zeros((W, W, 4), np.uint8)

    def put(self, x, y, color):
        if 0 <= x < W and 0 <= y < W:
            self.px[y, x] = (*color, 255)

    def get(self, x, y):
        return self.px[y, x, 3] > 0 if 0 <= x < W and 0 <= y < W else False

    def pick(self, colors, t):
        t = min(max(t, 0.0), 0.999)
        return colors[int(t * len(colors))]

    def blob(self, cx, cy, rx, ry, colors, inside=None, bias=0.0):
        # Shaded ellipsoid: normal from the ellipse, lit from the top left.
        for y in range(W):
            for x in range(W):
                nx = (x + 0.5 - cx) / rx
                ny = (y + 0.5 - cy) / ry
                d = nx * nx + ny * ny
                if d > 1.0 or (inside is not None and not inside(x, y)):
                    continue
                nz = math.sqrt(max(0.0, 1.0 - d))
                shade = max(0.0, nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2])
                self.put(x, y, self.pick(colors, 0.12 + 0.88 * shade + bias))

    def fill(self, test, color_at):
        for y in range(W):
            for x in range(W):
                if test(x + 0.5, y + 0.5):
                    self.put(x, y, color_at(x, y))

    def line(self, points, color):
        for (x0, y0), (x1, y1) in zip(points, points[1:]):
            steps = max(abs(x1 - x0), abs(y1 - y0))
            for i in range(steps + 1):
                t = i / max(1, steps)
                self.put(round(x0 + (x1 - x0) * t), round(y0 + (y1 - y0) * t), color)

    def outline(self, color=INK):
        solid = self.px[..., 3] > 0
        edge = np.zeros_like(solid)
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            edge |= np.roll(np.roll(solid, dy, axis=0), dx, axis=1)
        edge &= ~solid
        self.px[edge] = (*color, 255)

    def image(self):
        return Image.fromarray(self.px, "RGBA")


def in_polygon(points):
    def test(x, y):
        inside = False
        j = len(points) - 1
        for i in range(len(points)):
            xi, yi = points[i]
            xj, yj = points[j]
            if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
                inside = not inside
            j = i
        return inside
    return test


def star_points(cx, cy, outer, inner, count=5, phase=-math.pi / 2):
    points = []
    for i in range(count * 2):
        radius = outer if i % 2 == 0 else inner
        a = phase + i * math.pi / count
        points.append((cx + math.cos(a) * radius, cy + math.sin(a) * radius))
    return points


def sparkle(c, x, y, color, size=1):
    c.put(x, y, color)
    for k in range(1, size + 1):
        for dx, dy in ((k, 0), (-k, 0), (0, k), (0, -k)):
            c.put(x + dx, y + dy, color)


# ---------- the seven currencies ----------

def brasa():
    c = Canvas()
    coal = ramp("3a0e06", "5e1508", "8c1f0a", "b8300e", "e0461a")
    c.blob(16, 21, 10.5, 7.5, coal)
    # Glowing cracks through the ember.
    hot = ramp("ff7a1a", "ffb030", "ffe070")
    for path, tone in (([(9, 20), (13, 19), (15, 22), (19, 20)], 1), ([(18, 24), (21, 21), (24, 22)], 0), ([(12, 24), (14, 23)], 0), ([(16, 17), (18, 18)], 2)):
        c.line(path, hot[tone])
    # Flames licking up from the top.
    flame = ramp("e0461a", "ff7a1a", "ffb030", "ffe070", "fff6c8")
    for fx, top, width in ((11, 7, 3.2), (16, 3, 4.2), (21, 8, 3.0)):
        def test(x, y, fx=fx, top=top, width=width):
            if y < top or y > 17:
                return False
            t = (y - top) / (17 - top)
            half = width * math.sin(min(1.0, t * 1.25) * math.pi / 2) * (1.0 - 0.35 * t)
            return abs(x - fx - 0.5 * math.sin(t * 3)) <= half
        c.fill(test, lambda x, y, fx=fx, top=top: flame[min(4, max(0, int(4 - (y - top) / (17 - top) * 4 + (0.8 if abs(x + 0.5 - fx) < 1.2 else 0))))])
    c.outline()
    c.put(13, 5, hexc("fff6c8"))
    return c


def coroa():
    c = Canvas()
    gold = ramp("6e3a08", "a8641a", "d88c20", "f0b830", "ffd85a", "fff4b0")
    outline = [(5, 24), (5, 11), (10, 17), (16, 7), (22, 17), (27, 11), (27, 24)]
    test = in_polygon(outline)
    c.fill(test, lambda x, y: c.pick(gold, 0.9 - (y - 7) / 17 * 0.55 - (x - 5) / 22 * 0.25))
    # Band.
    c.fill(lambda x, y: 5 <= x <= 27 and 21 <= y <= 26, lambda x, y: gold[1] if y > 25 else (gold[3] if y < 23 else gold[2]))
    for x in range(6, 27):
        c.put(x, 21, gold[5] if x < 18 else gold[4])
    # Gems in the band and balls on the points.
    for gx, color in ((10, "e0302a"), (16, "3a8bff"), (22, "e0302a")):
        c.put(gx, 23, hexc(color))
        c.put(gx + 1, 23, hexc(color))
        c.put(gx, 24, tuple(max(0, v - 70) for v in hexc(color)))
        c.put(gx + 1, 24, tuple(max(0, v - 70) for v in hexc(color)))
        c.put(gx, 23, tuple(min(255, v + 90) for v in hexc(color)))
    for bx, by in ((5, 10), (16, 6), (27, 10)):
        c.blob(bx + 0.5, by + 0.5, 2.2, 2.2, gold)
    c.outline()
    sparkle(c, 25, 4, hexc("fffbe0"), 1)
    return c


def estrela():
    c = Canvas()
    gold = ramp("8a5208", "d89020", "f8c030", "ffe070", "fff6c0", "ffffff")
    points = star_points(16, 17, 14.5, 6.2)
    test = in_polygon(points)

    def shade(x, y):
        # Facets: each arm lit on its upper-left half.
        a = math.atan2(y + 0.5 - 17, x + 0.5 - 16)
        arm = (a + math.pi / 2) % (2 * math.pi / 5) - math.pi / 5
        base = 0.55 - (math.hypot(x + 0.5 - 16, y + 0.5 - 17) / 15) * 0.35
        return c.pick(gold, base + (0.28 if arm < 0 else -0.05) + (0.1 if y < 15 else 0))
    c.fill(test, shade)
    c.put(15, 15, gold[5])
    c.put(16, 15, gold[5])
    c.put(15, 16, gold[4])
    c.outline()
    sparkle(c, 27, 5, hexc("fff6c0"), 2)
    sparkle(c, 4, 26, hexc("ffe070"), 1)
    return c


def tormenta():
    c = Canvas()
    orb = ramp("160c34", "2a1a6a", "4a2ea8", "6e4ad8", "a08aff", "dcd2ff")
    c.blob(16, 16, 12.5, 12.5, orb)
    # Swirling clouds.
    cloud = hexc("8a74e8")
    for i in range(30):
        a = i * 0.3
        r = 4 + i * 0.28
        if i % 4 != 3:
            c.put(round(16 + math.cos(a) * r), round(16 + math.sin(a) * r * 0.8), cloud if i % 3 else hexc("c0b0ff"))
    # Lightning bolt with its own dark edge.
    bolt = [(21, 2), (9, 17), (16, 17), (10, 30), (25, 12), (18, 12), (24, 2)]
    inside = in_polygon(bolt)
    edge = lambda x, y: inside(x, y) or inside(x - 1, y) or inside(x + 1, y) or inside(x, y - 1) or inside(x, y + 1)
    c.fill(edge, lambda x, y: hexc("3a1a06"))
    c.fill(inside, lambda x, y: hexc("fff6b0") if x + y * 0.3 < 21 else hexc("ffd24a"))
    c.outline()
    c.put(10, 8, orb[5])
    c.put(9, 9, orb[5])
    return c


def solar():
    c = Canvas()
    rays = ramp("b8500a", "e07a14", "f8a828", "ffd24a")
    for i in range(12):
        a = i * math.pi / 6 - math.pi / 2
        long = i % 2 == 0
        tip = 15.5 if long else 12.5
        width = 0.2 if long else 0.24
        points = [(16 + math.cos(a - width) * 8, 16 + math.sin(a - width) * 8), (16 + math.cos(a) * tip, 16 + math.sin(a) * tip), (16 + math.cos(a + width) * 8, 16 + math.sin(a + width) * 8)]
        c.fill(in_polygon(points), lambda x, y, long=long: rays[3] if long else rays[2])
    disk = ramp("a8400a", "e07a14", "f8a828", "ffd24a", "fff0a0", "fffbe0")
    c.blob(16, 16, 9.2, 9.2, disk, bias=0.08)
    # Inner ring, the "divine" mark.
    for i in range(40):
        a = i * math.tau / 40
        c.put(round(16 + math.cos(a) * 5.4 - 0.5), round(16 + math.sin(a) * 5.4 - 0.5), hexc("fff6c8") if a > math.pi else hexc("f0a020"))
    c.outline()
    return c


def eclipse():
    c = Canvas()
    corona = ramp("f07a14", "ffb030", "ffe070", "fff6c8")
    for y in range(W):
        for x in range(W):
            d = math.hypot(x + 0.5 - 16, y + 0.5 - 16)
            a = math.atan2(y + 0.5 - 16, x + 0.5 - 16)
            glow = 0.5 + 0.5 * math.cos(a + 2.4)
            if 9.5 < d <= 12.0 + 2.5 * glow:
                c.put(x, y, c.pick(corona, glow * 0.95 + (0.15 if d < 11.5 else -0.15)))
    # Flares from the brightest side.
    for a, length in ((-2.4, 17), (-2.0, 15.5), (-2.8, 15.5), (-1.6, 14.5)):
        c.line([(round(16 + math.cos(a) * 13), round(16 + math.sin(a) * 13)), (round(16 + math.cos(a) * length), round(16 + math.sin(a) * length))], corona[3])
    moon = ramp("0c0612", "1a1024", "2a1a3a", "3e2a52")
    c.blob(17.2, 17.2, 10.2, 10.2, moon)
    c.outline()
    c.put(9, 10, hexc("fff6c8"))
    return c


def espelho():
    c = Canvas()
    frame = ramp("6e3a08", "a8641a", "e0a02a", "ffd85a", "fff4b0")
    # Handle.
    c.fill(lambda x, y: 14 <= x <= 17 and 21 <= y <= 29, lambda x, y: frame[3] if x == 14 else (frame[1] if x == 17 else frame[2]))
    c.blob(16, 29.5, 3.2, 2.0, frame)
    # Frame and glass.
    c.blob(16, 12.5, 11.5, 11.0, frame)
    glass = ramp("123a6a", "1f5e9a", "3a8bd0", "6ec0f0", "b8ecff", "ffffff")

    def glass_at(x, y):
        t = 0.2 + (x - 7) / 18 * 0.25 + (1 - (y - 3) / 19) * 0.3
        if 3 <= (x - 8) + (y - 5) * 0.9 <= 6 or 9 <= (x - 8) + (y - 5) * 0.9 <= 10:
            t += 0.45
        return c.pick(glass, t)
    c.fill(lambda x, y: ((x - 16) / 8.8) ** 2 + ((y - 12.5) / 8.4) ** 2 <= 1.0, glass_at)
    for gx, gy in ((16, 1), (5, 12), (27, 12)):
        c.put(gx, gy, hexc("7ad8ff"))
    c.outline()
    sparkle(c, 25, 5, hexc("ffffff"), 1)
    return c


ICONS = {"brasa": brasa, "coroa": coroa, "estrela": estrela, "tormenta": tormenta, "solar": solar, "eclipse": eclipse, "espelho": espelho}


def main():
    os.makedirs(OUT, exist_ok=True)
    images = []
    for name, draw in ICONS.items():
        image = draw().image()
        image.save(os.path.join(OUT, name + ".png"))
        images.append(image)
    if "--preview" in sys.argv:
        target = sys.argv[sys.argv.index("--preview") + 1]
        sheet = Image.new("RGBA", (len(images) * 40 * 6, 40 * 6), (74, 50, 32, 255))
        for i, image in enumerate(images):
            sheet.paste(image.resize((32 * 6, 32 * 6), Image.NEAREST), (i * 240 + 24, 24), image.resize((32 * 6, 32 * 6), Image.NEAREST))
        sheet.save(target)
    print("wrote %d icons to %s" % (len(images), os.path.normpath(OUT)))


if __name__ == "__main__":
    main()
