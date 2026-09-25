#!/usr/bin/env python3
"""Copy one PixelLab character state (+ its prone state) into assets/characters/<skin>/.

The zip is the character group download (https://api.pixellab.ai/mcp/characters/<id>/download),
which holds one <State_Name>/ folder per state with rotations and animations.

Usage: python tools/import_pixellab_skin.py <group.zip> <Standing_State> <Prone_State> <skin>
Prone clips named prone_idle / prone_crawl / prone_shoot become prone/{idle,crawl,shoot}/.
If the prone east view faces left (head on the left) east/west are swapped and clips mirrored.
"""
import io
import os
import sys
import zipfile

import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), "..", "assets", "characters")


def faces_left(image):
    alpha = np.array(image.convert("RGBA"))[:, :, 3] > 40
    ys, xs = np.nonzero(alpha)
    top = ys.min()
    head = xs[ys < top + (ys.max() - top) * 0.35]
    return head.mean() < (xs.min() + xs.max()) / 2


def main(archive, standing, prone, skin):
    target = os.path.join(ROOT, skin)
    os.makedirs(os.path.join(target, "prone"), exist_ok=True)
    with zipfile.ZipFile(archive) as bundle:
        names = bundle.namelist()

        def read(name):
            return Image.open(io.BytesIO(bundle.read(name))).convert("RGBA")

        for direction in ("south", "east", "north", "west"):
            read(f"{standing}/rotations/{direction}.png").save(os.path.join(target, f"{direction}.png"))
        east = read(f"{prone}/rotations/east.png")
        west = read(f"{prone}/rotations/west.png")
        mirrored = faces_left(east)
        if mirrored:
            east, west = west, east
        east.save(os.path.join(target, "prone", "east.png"))
        west.save(os.path.join(target, "prone", "west.png"))
        for direction in ("south", "north"):
            read(f"{prone}/rotations/{direction}.png").save(os.path.join(target, "prone", f"{direction}.png"))
        for clip in ("idle", "crawl", "shoot"):
            prefix = f"{prone}/animations/prone_{clip}/east/"
            frames = sorted(n for n in names if n.startswith(prefix) and n.endswith(".png"))
            if not frames:
                continue
            folder = os.path.join(target, "prone", clip)
            os.makedirs(folder, exist_ok=True)
            for old in os.listdir(folder):
                if old.startswith("frame_"):
                    os.remove(os.path.join(folder, old))
            for i, name in enumerate(frames):
                frame = read(name)
                if mirrored:
                    frame = frame.transpose(Image.FLIP_LEFT_RIGHT)
                frame.save(os.path.join(folder, f"frame_{i:02d}.png"))
    print(skin, "mirrored" if mirrored else "ok")


if __name__ == "__main__":
    main(*sys.argv[1:5])
