#!/usr/bin/env python3
"""Build the evolved weapon icons (+9, +10, +12) from each PixelLab tier0 icon.

DDTank weapons change look as they are strengthened; here every weapon gets
  tier1 (+9)  steel-blue finish with a blue glow,
  tier2 (+10) violet crystal finish with a purple glow,
  tier3 (+12) gold finish with a red glow and sparkles,
by mapping luminance onto a colour ramp (outlines stay dark) and adding a glow ring.

Usage: python tools/weapon_tiers.py   (reads/writes assets/weapons/<id>/tier*.png)
"""
import os

import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), "..", "assets", "weapons")

RAMPS = {
    1: ([20, 34, 70], [70, 140, 230], [200, 236, 255], (90, 180, 255)),
    2: ([36, 14, 64], [150, 80, 230], [240, 210, 255], (190, 110, 255)),
    3: ([70, 34, 6], [240, 176, 40], [255, 250, 200], (255, 70, 60)),
}
MIX = {1: 0.62, 2: 0.66, 3: 0.72}


def ramp(t, dark, mid, light):
    t = t[..., None]
    low = np.array(dark) + (np.array(mid) - np.array(dark)) * (t / 0.55)
    high = np.array(mid) + (np.array(light) - np.array(mid)) * ((t - 0.55) / 0.45)
    return np.where(t < 0.55, low, high)


def evolve(base, tier):
    img = np.array(base).astype(np.float32)
    rgb, alpha = img[..., :3], img[..., 3]
    luma = (rgb @ np.array([0.299, 0.587, 0.114])) / 255.0
    dark, mid, light, glow = RAMPS[tier]
    lo, hi = np.percentile(luma[alpha > 128], [5, 97])
    t = np.clip((luma - lo) / max(0.05, hi - lo), 0, 1)
    tinted = ramp(t, dark, mid, light)
    mix = MIX[tier] * (luma > 0.16)  # keep the dark outline
    out = rgb * (1 - mix[..., None]) + tinted * mix[..., None]
    result = np.dstack([np.clip(out, 0, 255), alpha]).astype(np.uint8)
    # Glow ring around the silhouette.
    solid = alpha > 128
    ring = np.zeros_like(solid)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            ring |= np.roll(np.roll(solid, dy, 0), dx, 1)
    ring &= ~solid
    result[ring] = (*glow, 170)
    if tier == 3:
        rng = np.random.default_rng(12)
        ys, xs = np.nonzero(solid)
        for i in rng.choice(len(xs), 6, replace=False):
            y, x = ys[i], xs[i]
            for dy, dx in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
                if 0 <= y + dy < result.shape[0] and 0 <= x + dx < result.shape[1]:
                    result[y + dy, x + dx] = (255, 255, 235, 255)
    return Image.fromarray(result, "RGBA")


if __name__ == "__main__":
    for weapon in sorted(os.listdir(ROOT)):
        source = os.path.join(ROOT, weapon, "tier0.png")
        if not os.path.exists(source):
            continue
        base = Image.open(source).convert("RGBA")
        for tier in (1, 2, 3):
            evolve(base, tier).save(os.path.join(ROOT, weapon, f"tier{tier}.png"))
        print(weapon)
