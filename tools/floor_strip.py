#!/usr/bin/env python3
"""Build a map's unbreakable floor ("hard" terrain piece) from a PixelLab strip.

The floor must cover the whole width of the map, but PixelLab gives at most 768 texels
(1536 world units). This cleans the strip like tools/terrain_pieces.py (largest body,
holes filled), crops the columns that read as flat ground, mirrors them side by side
until the width is covered (a mirror seam always matches) and pushes the jagged
underside down so no gap is left under the ground. The piece is placed in
shared/balance/combat.json with "hard": true, at y = world height - piece height * 2.

Usage: python tools/floor_strip.py <source.png> <name> <width_texels> [--crop x0:x1] [--extend rows] [--key]
  --crop    columns of the cleaned strip to repeat (default: all)
  --extend  rows added under the ground by cycling its last rows (default 24)
  --key     the strip came back on a flat grey backdrop: flood-fill it away
Output: assets/maps/terrain/<name>.png (1 texel = 2 world units).
"""
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
import terrain_pieces  # noqa: E402


def build(source, width, crop=None, extend=24, key=False):
    piece, _ = terrain_pieces.clean(source, key=key, main=True)
    img = np.array(piece)
    if crop:
        img = img[:, crop[0]:crop[1]]
    tile_w = img.shape[1]
    tiles = []
    while sum(t.shape[1] for t in tiles) < width:
        tiles.append(img if len(tiles) % 2 == 0 else img[:, ::-1])
    strip = np.concatenate(tiles, axis=1)[:, :width].copy()
    # Extend the jagged underside: cycle a 16-row band just above each column's bottom
    # (the bottom rows are outline and shadow, so they are skipped).
    h = strip.shape[0]
    out = np.zeros((h + extend, width, 4), np.uint8)
    out[:h] = strip
    for x in range(width):
        solid = np.nonzero(strip[:, x, 3] >= 128)[0]
        if len(solid) == 0:
            continue
        bottom = int(solid.max())
        for k in range(1, h + extend - bottom):
            src = max(0, bottom - 24 + (k - 1) % 16)
            out[bottom + k, x] = strip[src, x]
    return Image.fromarray(out, "RGBA"), tile_w


def main(args):
    source, name, width = args[0], args[1], int(args[2])
    crop = extend = None
    flags = args[3:]
    crop = None
    extend = 24
    for i, flag in enumerate(flags):
        if flag == "--crop":
            a, b = flags[i + 1].split(":")
            crop = (int(a), int(b))
        if flag == "--extend":
            extend = int(flags[i + 1])
    piece, tile_w = build(source, width, crop, extend, "--key" in flags)
    piece.save(os.path.join(terrain_pieces.OUT, name + ".png"))
    print(f"{name}: {piece.width}x{piece.height} texels = {piece.width * 2}x{piece.height * 2} world (tile {tile_w} texels)")


if __name__ == "__main__":
    main(sys.argv[1:])
