#!/usr/bin/env python3
"""Gustfire logo in pixel art (website, store and, later, the title screen).

The letters come from Titan One (SIL OFL, tools/logo/TitanOne-OFL.txt), laid on an arch
at 4x, then reduced to native pixels and painted like hand-made pixel art: stepped
gradient bands with a dithered seam, a bevel, a gloss band, dark outline, a 3D
extrusion and an outer rim. "GUST" is painted in wind colours and "FIRE" in fire
colours. The winged bomb (tools/logo/emblem_bomb.png) is PixelLab art; the dashed shot
arc is the same "tracejado" the game draws after a shot.

Usage:  python tools/make_logo.py [--out website/img/brand] [--preview preview.png]

Writes, for each language (en, pt):
  gustfire_logo_<lang>.png       native pixels, transparent
  gustfire_logo_<lang>@3x.png    3x nearest neighbour (hero, store capsules)
and gustfire_wordmark.png / @3x (letters only), gustfire_icon_{32,64,180,512}.png.
"""
import argparse
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
TITAN = os.path.join(ROOT, "tools", "logo", "TitanOne-Regular.ttf")
PIXEL_FONT = os.path.join(ROOT, "assets", "fonts", "PixelOperator-Bold.ttf")
EMBLEM = os.path.join(ROOT, "tools", "logo", "emblem_bomb.png")

SS = 4            # supersampling of the letter shapes
CAP = 74          # cap height in native pixels
ARCH = 13         # how much the middle of the word rises
TILT = 1.6        # alternating tilt of the letters (degrees), for a bouncy word
TAGLINES = {"en": "SKY ARTILLERY", "pt": "ARTILHARIA NOS CÉUS"}


def hexc(value):
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4)) + (255,)


# Top to bottom. The jump between the 4th and 5th colour is the "horizon" of the gloss.
PALETTES = {
    "gust": {
        "bands": ["ffffff", "e6fbff", "b5efff", "7fdcff", "3aa6ff", "2a86f0", "1f66d6", "1a4fb8"],
        "light": "ffffff", "dark": "143e9a", "gloss": "ffffff",
        "extrude": ["1f4fb0", "18408f", "123274", "0d2658"], "extrude_edge": "3d74d8",
    },
    "fire": {
        "bands": ["fffbe0", "fff09a", "ffd94a", "ffc21f", "ff9a12", "ff7a14", "f2561a", "d23a16"],
        "light": "fffbe8", "dark": "a82a0e", "gloss": "fffdf0",
        "extrude": ["a3300e", "85240b", "681a08", "4e1206"], "extrude_edge": "d2541c",
    },
}
BAND_STOPS = [0.0, 0.10, 0.2, 0.33, 0.47, 0.62, 0.78, 0.92]   # v where each band starts
OUTLINE = hexc("1a0f2e")
RIM = hexc("fff6e0")
SHADOW = (12, 6, 26, 150)


def disk(r):
    y, x = np.ogrid[-r:r + 1, -r:r + 1]
    return x * x + y * y <= r * r + r


def dilate(mask, r):
    return ndimage.binary_dilation(mask, structure=disk(r)) if r > 0 else mask.copy()


def shift(mask, dx, dy):
    out = np.zeros_like(mask)
    h, w = mask.shape
    out[max(dy, 0):h + min(dy, 0), max(dx, 0):w + min(dx, 0)] = \
        mask[max(-dy, 0):h + min(-dy, 0), max(-dx, 0):w + min(-dx, 0)]
    return out


class Word:
    """The letters on an arch: one boolean mask per letter plus where each baseline is."""

    def __init__(self, text, groups, width, height, cx, base_y):
        size = CAP / 0.71
        font = ImageFont.truetype(TITAN, int(size * SS))
        spacing = -1.5 * SS
        advances = [font.getlength(ch) + spacing for ch in text]
        total = sum(advances) - spacing
        half = total / 2
        x = cx * SS - half
        self.masks, self.baselines, self.groups = [], [], []
        for index, (ch, adv, group) in enumerate(zip(text, advances, groups)):
            left, top, right, bottom = font.getbbox(ch)
            centre = x + (right - left) / 2
            t = (centre - cx * SS) / half
            lift = ARCH * SS * (1 - t * t)
            slope = 2 * ARCH * SS * t / half
            angle = -math.degrees(math.atan(slope)) + (TILT if index % 2 else -TILT)
            pad = 24 * SS
            glyph = Image.new("L", (right - left + 2 * pad, bottom - top + 2 * pad), 0)
            ImageDraw.Draw(glyph).text((pad - left, pad - top), ch, font=font, fill=255)
            # Rotate around the baseline centre so the letter stays seated on the arch.
            pivot = (glyph.width / 2, pad + (97 / 100 * size * SS - top))
            glyph = glyph.rotate(angle, resample=Image.BICUBIC, center=pivot)
            layer = Image.new("L", (width * SS, height * SS), 0)
            baseline = base_y * SS - lift
            layer.paste(glyph, (int(x - pad), int(baseline - pivot[1])))
            small = layer.resize((width, height), Image.BOX)
            self.masks.append(np.array(small) >= 128)
            self.baselines.append(baseline / SS)
            self.groups.append(group)
            x += adv
        self.fill = np.zeros((height, width), bool)
        for mask in self.masks:
            self.fill |= mask


def band_colour(palette, v, x, y):
    bands = palette["bands"]
    index = 0
    for i, stop in enumerate(BAND_STOPS):
        if v >= stop:
            index = i
    # Checkerboard dither on the row that touches the next band.
    if index + 1 < len(BAND_STOPS):
        nxt = BAND_STOPS[index + 1]
        if nxt - v < 0.022 and (x + y) % 2 == 0:
            index += 1
    return hexc(bands[index])


def paint_word(word, rim=True, extrude=6):
    h, w = word.fill.shape
    img = np.zeros((h, w, 4), np.uint8)
    fill = word.fill
    body = dilate(fill, 2)                      # letters + dark outline
    # 3D extrusion: the outlined letters pushed down and a little right.
    depth = np.zeros_like(fill)
    depth_step = np.full((h, w), -1, int)
    for k in range(extrude, 0, -1):
        moved = shift(body, k // 3, k)
        depth |= moved
        depth_step[moved] = k
    depth &= ~body
    silhouette = body | depth
    outer = dilate(silhouette, 2)
    rim_mask = dilate(outer, 3) if rim else outer
    # Outermost: a soft shadow, the light rim and the dark outline.
    shadow = shift(dilate(rim_mask, 1), 2, 4) & ~rim_mask
    img[shadow] = SHADOW
    img[rim_mask & ~outer] = RIM
    edge = rim_mask & ~outer
    # A darker line inside the rim keeps it from looking flat.
    img[edge & ~shift(dilate(outer, 1), 0, 1)] = hexc("f3dcb0")
    img[outer] = OUTLINE
    # Owner of each extrusion pixel: the letter just above it.
    owner = np.full((h, w), -1, int)
    for i, mask in enumerate(word.masks):
        grown = dilate(mask, 2)
        for k in range(1, extrude + 1):
            owner[shift(grown, k // 3, k) & depth & (owner < 0)] = i
    for i, group in enumerate(word.groups):
        pal = PALETTES[group]
        mine = depth & (owner == i)
        ys, xs = np.nonzero(mine)
        for y, x in zip(ys, xs):
            k = depth_step[y, x]
            shade = min(len(pal["extrude"]) - 1, int((k - 1) / extrude * len(pal["extrude"])))
            img[y, x] = hexc(pal["extrude"][shade])
        # Light edge on the left side of the extrusion.
        left_edge = mine & ~shift(mine, 1, 0)
        img[left_edge & ~body] = hexc(pal["extrude_edge"])
    # The dark outline around each letter (drawn over the extrusion).
    img[body & ~fill] = OUTLINE
    # Fill with the gradient, bevel and gloss.
    top_left = fill & ~(shift(fill, 1, 1) & shift(fill, 0, 1) & shift(fill, 1, 0))
    top_left2 = fill & ~(shift(fill, 2, 2) & shift(fill, 0, 2) & shift(fill, 2, 0))
    bottom_right = fill & ~(shift(fill, -1, -1) & shift(fill, 0, -1) & shift(fill, -1, 0))
    bottom_right2 = fill & ~(shift(fill, -2, -2) & shift(fill, 0, -2) & shift(fill, -2, 0))
    for i, (mask, baseline, group) in enumerate(zip(word.masks, word.baselines, word.groups)):
        pal = PALETTES[group]
        top = baseline - CAP
        ys, xs = np.nonzero(mask)
        for y, x in zip(ys, xs):
            v = (y - top) / CAP
            colour = band_colour(pal, v, x, y)
            if bottom_right[y, x]:
                colour = hexc(pal["dark"])
            elif bottom_right2[y, x] and v > 0.45:
                colour = hexc(pal["bands"][-1])
            elif top_left[y, x]:
                colour = hexc(pal["light"])
            elif top_left2[y, x] and v < 0.45:
                colour = hexc(pal["light"])
            img[y, x] = colour
        # Gloss: a short bright streak in the upper left of each letter.
        gloss = mask & ~top_left2 & ~bottom_right2
        gy0 = int(top + CAP * 0.14)
        for y in range(gy0, gy0 + 3):
            row = np.nonzero(gloss[y])[0] if 0 <= y < gloss.shape[0] else []
            if len(row) > 6:
                start = row[0] + 2
                for x in range(start, min(start + max(3, len(row) // 4) - (y - gy0), row[-1] - 2)):
                    if gloss[y, x]:
                        img[y, x] = hexc(pal["gloss"])
    return Image.fromarray(img, "RGBA")


def sparkle(draw, x, y, size, colour=(255, 255, 255, 255)):
    """A four-point pixel star."""
    for i in range(-size, size + 1):
        draw.point((x + i, y), fill=colour)
        draw.point((x, y + i), fill=colour)
    if size >= 3:
        for d in (-1, 1):
            draw.point((x + d, y + d), fill=colour)
            draw.point((x + d, y - d), fill=colour)


def dashed_arc(canvas, start, apex, end, dash=7, gap=5, width=3):
    """The shot line: two parabolas meeting at the apex, dashed, white with a dark edge."""
    pts = []
    for (ax, ay), (bx, by), rising in ((start, apex, True), (apex, end, False)):
        steps = int(abs(bx - ax) * 3) + 1
        for s in range(steps + 1):
            t = s / steps
            x = ax + (bx - ax) * t
            if rising:
                y = ay + (by - ay) * (1 - (1 - t) ** 2)
            else:
                y = ay + (by - ay) * t * t
            pts.append((x, y))
    # Walk the path and keep the "on" stretches.
    run, on, dist, dashes = [], True, 0.0, []
    for a, b in zip(pts, pts[1:]):
        seg = math.dist(a, b)
        dist += seg
        if on:
            run.append(b)
        if on and dist >= dash:
            dashes.append(run)
            run, on, dist = [], False, 0.0
        elif not on and dist >= gap:
            run, on, dist = [b], True, 0.0
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for run in dashes:
        if len(run) > 1:
            d.line(run, fill=OUTLINE, width=width + 2)
    for run in dashes:
        if len(run) > 1:
            d.line(run, fill=(255, 255, 255, 255), width=width)
    return layer


def wind_streaks(canvas_size, end_x, top):
    """Gust lines blowing into the word: straight strokes ending in a curl that turns up
    and back, white with a blue underside."""
    layer = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    # (y, length, curl radius, width, gap before the word)
    for y, length, curl, width, gap in ((top + 20, 70, 8, 3, 10), (top + 42, 96, 10, 3, 6), (top + 64, 54, 6, 2, 12)):
        x1 = end_x - gap - curl
        x0 = x1 - length
        for colour, off in (((40, 120, 230, 255), 1), ((255, 255, 255, 255), 0)):
            d.line([(x0, y + off), (x1, y + off)], fill=colour, width=width)
            # Curl: three quarters of a circle above the end of the line.
            d.arc([x1 - curl, y - 2 * curl + off, x1 + curl, y + off], 180, 90, fill=colour, width=width)
        # A short trailing dash behind each line.
        d.line([(x0 - 14, y + 1), (x0 - 6, y + 1)], fill=(40, 120, 230, 255), width=width)
        d.line([(x0 - 14, y), (x0 - 6, y)], fill=(255, 255, 255, 255), width=width)
    arr = np.array(layer)
    arr[..., 3] = np.where(arr[..., 3] >= 128, 255, 0)
    return Image.fromarray(arr, "RGBA")


def embers(canvas_size, box, count=14, seed=5):
    """Sparks rising from the fire letters."""
    rng = np.random.default_rng(seed)
    layer = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    x0, y0, x1, y1 = box
    for _ in range(count):
        x = int(rng.uniform(x0, x1))
        y = int(rng.uniform(y0, y1))
        size = int(rng.choice([1, 2, 2, 3]))
        core = [hexc("fff09a"), hexc("ffc21f"), hexc("ff7a14")][int(rng.integers(0, 3))]
        d.rectangle([x, y + 1, x + size, y + size], fill=hexc("c8401a"))
        d.rectangle([x, y, x + size - 1, y + size - 1], fill=core)
    return layer


def ribbon(text, width):
    """A red banner with folded tails and the tagline in Pixel Operator Bold."""
    font = ImageFont.truetype(PIXEL_FONT, 16)
    text_w = int(font.getlength(text)) + len(text)   # 1 px of extra tracking
    body_w = max(text_w + 34, 150)
    h = 22
    tail = 16
    w = body_w + 2 * tail
    img = Image.new("RGBA", (w + 4, h + 10), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    dark, red, red_hi, red_lo, gold = OUTLINE, hexc("d8283a"), hexc("ff5a5f"), hexc("9c1830"), hexc("ffcf4a")
    # Tails (behind, lower).
    for side in (0, 1):
        x0 = 2 if side == 0 else w + 2 - tail - 6
        pts = [(x0, 8), (x0 + tail + 6, 8), (x0 + tail + 6, h + 8), (x0, h + 8), (x0 + 6, h // 2 + 8)]
        if side == 1:
            pts = [(x0, 8), (x0 + tail + 6, 8), (x0 + tail, h // 2 + 8), (x0 + tail + 6, h + 8), (x0, h + 8)]
        d.polygon(pts, fill=red_lo, outline=dark)
    # Body.
    bx0, bx1 = tail + 2, tail + 2 + body_w
    d.rectangle([bx0, 2, bx1, h + 2], fill=red, outline=dark)
    d.line([(bx0 + 1, 3), (bx1 - 1, 3)], fill=red_hi)
    d.line([(bx0 + 1, 4), (bx1 - 1, 4)], fill=gold)
    d.line([(bx0 + 1, h), (bx1 - 1, h)], fill=gold)
    d.line([(bx0 + 1, h + 1), (bx1 - 1, h + 1)], fill=red_lo)
    # Folds where the tails meet the body.
    for fx in (bx0, bx1):
        d.line([(fx, h + 2), (fx + (4 if fx == bx0 else -4), h + 8)], fill=dark)
    # Text with a 1 px shadow and 1 px tracking.
    x = bx0 + (body_w - text_w) // 2 + 1
    y = 5
    for ch in text:
        d.text((x + 1, y + 1), ch, font=font, fill=red_lo)
        d.text((x, y), ch, font=font, fill=hexc("fff4d6"))
        x += font.getlength(ch) + 1
    # Keep it pixel-perfect: no half-transparent pixels from the font.
    arr = np.array(img)
    arr[..., 3] = np.where(arr[..., 3] >= 128, 255, 0)
    return Image.fromarray(arr, "RGBA")


def build_logo(lang, emblem=True, tagline=True, extras=True):
    W, H = 760, 300
    cx, base_y = W // 2, 214
    word = Word("GUSTFIRE", ["gust"] * 4 + ["fire"] * 4, W, H, cx, base_y)
    canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    xs = np.nonzero(word.fill.any(axis=0))[0]
    ys = np.nonzero(word.fill.any(axis=1))[0]
    left, right, top = xs[0], xs[-1], ys[0]
    bomb = Image.open(EMBLEM).convert("RGBA")
    bomb = bomb.crop(bomb.getbbox())
    bomb_y = int(top - bomb.height + 16)
    if extras:
        # The shot: from the lower left, up to the bomb at the apex, down to a burst past the E.
        apex = (cx, bomb_y + bomb.height * 0.62)
        canvas.alpha_composite(dashed_arc(canvas, (left - 20, base_y - 6), apex, (right + 14, top + 10)))
        canvas.alpha_composite(wind_streaks(canvas.size, left, top))
        burst = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        d = ImageDraw.Draw(burst)
        bx, by = right + 14, top + 10
        for r, colour in ((17, OUTLINE), (15, hexc("ff7a14")), (11, hexc("ffc21f")), (7, hexc("fff09a")), (3, (255, 255, 255, 255))):
            pts = []
            for k in range(16):
                ang = k * math.pi / 8 + 0.2
                rr = r if k % 2 == 0 else r * 0.5
                pts.append((bx + rr * math.cos(ang), by + rr * math.sin(ang)))
            d.polygon(pts, fill=colour)
        canvas.alpha_composite(burst)
        fire_left = int(np.nonzero(word.masks[4].any(axis=0))[0][0])
        canvas.alpha_composite(embers(canvas.size, (fire_left + 10, top - 26, right - 20, top - 4)))
    if emblem:
        canvas.alpha_composite(bomb, (cx - bomb.width // 2, bomb_y))
    canvas.alpha_composite(paint_word(word))
    if extras:
        d = ImageDraw.Draw(canvas)
        for x, y, s in ((left + 44, top + 4, 3), (right - 76, top - 2, 2), (right - 6, base_y + 6, 2), (left + 160, base_y + 12, 2)):
            sparkle(d, x, y, s)
    if tagline:
        band = ribbon(TAGLINES[lang], W)
        canvas.alpha_composite(band, (cx - band.width // 2, base_y + 20))
    return canvas.crop(canvas.getbbox())


def icon():
    """The winged bomb on a round sky badge, for favicons and app icons."""
    bomb = Image.open(EMBLEM).convert("RGBA")
    bomb = bomb.crop(bomb.getbbox())
    size = 144
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([2, 2, size - 3, size - 3], fill=OUTLINE)
    d.ellipse([6, 6, size - 7, size - 7], fill=hexc("ffcf4a"))
    d.ellipse([9, 9, size - 10, size - 10], fill=hexc("2a86f0"))
    d.ellipse([12, 12, size - 13, size - 40], fill=hexc("3aa6ff"))
    scale = (size - 16) / bomb.width
    bomb = bomb.resize((int(bomb.width * scale), int(bomb.height * scale)), Image.NEAREST)
    img.alpha_composite(bomb, ((size - bomb.width) // 2, (size - bomb.height) // 2 + 4))
    return img


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default=os.path.join(ROOT, "website", "img", "brand"))
    parser.add_argument("--preview", default="")
    args = parser.parse_args()
    os.makedirs(args.out, exist_ok=True)

    def save(img, name, scales=(1, 3)):
        for s in scales:
            suffix = "" if s == 1 else f"@{s}x"
            out = img if s == 1 else img.resize((img.width * s, img.height * s), Image.NEAREST)
            out.save(os.path.join(args.out, f"{name}{suffix}.png"), optimize=True)

    logos = {}
    for lang in TAGLINES:
        logos[lang] = build_logo(lang)
        save(logos[lang], f"gustfire_logo_{lang}")
    save(build_logo("en", emblem=False, tagline=False, extras=False), "gustfire_wordmark")
    badge = icon()
    for s in (32, 64, 180, 512):
        badge.resize((s, s), Image.NEAREST if s >= 144 else Image.LANCZOS).save(
            os.path.join(args.out, f"gustfire_icon_{s}.png"), optimize=True)
    print("logos", {k: v.size for k, v in logos.items()}, "->", os.path.relpath(args.out, ROOT))

    if args.preview:
        logo = logos["en"]
        backs = [(28, 22, 48), (120, 190, 240), (245, 236, 220)]
        sheet = Image.new("RGBA", (logo.width * 2 + 30, (logo.height * 2 + 20) * len(backs)), (0, 0, 0, 255))
        for i, colour in enumerate(backs):
            panel = Image.new("RGBA", (logo.width * 2 + 30, logo.height * 2 + 20), colour + (255,))
            panel.alpha_composite(logo.resize((logo.width * 2, logo.height * 2), Image.NEAREST), (15, 10))
            sheet.alpha_composite(panel, (0, i * (logo.height * 2 + 20)))
        sheet.save(args.preview)


if __name__ == "__main__":
    main()
