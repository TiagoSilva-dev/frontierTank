#!/usr/bin/env python3
"""Clean PixelLab island paintings into destructible terrain pieces.

DDTank maps are painted foregrounds whose alpha is the collision shape. Each
PixelLab island (side view, transparent background) becomes one piece:
  - alpha is made binary (>= 128 is ground),
  - loose specks (pebbles, drips floating under the island) are dropped,
  - holes inside the body are filled so craters are the only way through,
  - the image is cropped to the ground's bounding box.
The result goes to assets/maps/terrain/<name>.png; 1 texel = 1 terrain mask pixel
(2 world units), so pieces are placed in shared/balance/combat.json by world
position and never rescaled.

Usage: python tools/terrain_pieces.py <source.png> <name> [--flip] [--key] [--main] [...]
  --flip  mirror horizontally
  --key   the painting came back on a flat grey/black backdrop: flood-fill it away
  --main  keep only the largest connected body
Prints each piece's size in world units.
"""
import os
import sys
from collections import deque

import numpy as np
from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "maps", "terrain")
MIN_SPECK = 60


def components(mask):
    h, w = mask.shape
    labels = np.zeros((h, w), np.int32)
    sizes = [0]
    for y in range(h):
        for x in range(w):
            if mask[y, x] and not labels[y, x]:
                label = len(sizes)
                count = 0
                queue = deque([(y, x)])
                labels[y, x] = label
                while queue:
                    cy, cx = queue.popleft()
                    count += 1
                    for ny, nx in ((cy + 1, cx), (cy - 1, cx), (cy, cx + 1), (cy, cx - 1)):
                        if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not labels[ny, nx]:
                            labels[ny, nx] = label
                            queue.append((ny, nx))
                sizes.append(count)
    return labels, sizes


def backdrop(img):
    # Flat low-saturation dark pixels (checkerboard greys, black) touching the border.
    rgb = img[..., :3].astype(np.int32)
    flat = (rgb.max(-1) - rgb.min(-1) <= 10) & (rgb.max(-1) < 150)
    labels, _ = components(np.pad(flat, 1, constant_values=True))
    return (labels == labels[0, 0])[1:-1, 1:-1]


def clean(source, flip=False, key=False, main=False):
    img = np.array(Image.open(source).convert("RGBA"))
    if flip:
        img = img[:, ::-1].copy()
    solid = img[..., 3] >= 128
    if key:
        solid &= ~backdrop(img)
    labels, sizes = components(solid)
    biggest = int(np.argmax(sizes))
    keep = np.zeros_like(solid)
    for label, size in enumerate(sizes):
        # The main body plus anything big enough to read as part of the island.
        if label and (label == biggest or (size >= MIN_SPECK and not main)):
            keep |= labels == label
    # Fill holes: empty pixels not reachable from the border are inside the body.
    outside, _ = components(np.pad(~keep, 1, constant_values=True))
    outside = outside[1:-1, 1:-1] == outside[0, 0]
    holes = ~keep & ~outside
    rgb = img[..., :3].astype(np.float32)
    if holes.any():
        fill = np.percentile(rgb[keep], 20, axis=0)
        rgb[holes] = fill
    keep |= holes
    out = np.dstack([rgb.astype(np.uint8), (keep * 255).astype(np.uint8)])
    ys, xs = np.nonzero(keep)
    out = out[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    return Image.fromarray(out, "RGBA"), int(holes.sum())


def main(args):
    os.makedirs(OUT, exist_ok=True)
    i = 0
    while i < len(args):
        source, name = args[i], args[i + 1]
        i += 2
        flags = set()
        while i < len(args) and args[i].startswith("--"):
            flags.add(args[i])
            i += 1
        piece, filled = clean(source, "--flip" in flags, "--key" in flags, "--main" in flags)
        piece.save(os.path.join(OUT, name + ".png"))
        print(f"{name}: {piece.width}x{piece.height} texels = {piece.width * 2}x{piece.height * 2} world, {filled} hole texels filled")


if __name__ == "__main__":
    main(sys.argv[1:])
