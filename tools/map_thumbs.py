#!/usr/bin/env python3
"""Render each battle map's thumbnail (backdrop + painted terrain) for the room screen.

Reads the maps in shared/balance/combat.json, lays the "terrain" pieces over the
backdrop in terrain texel space (1 texel = 2 world units), crops the band around the
ground and writes assets/maps/thumbs/<id>.png at 368x156 (the location picker shows
it at 184x78).

Usage: python tools/map_thumbs.py
"""
import json
import os

from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), "..")
OUT = os.path.join(ROOT, "assets", "maps", "thumbs")
SIZE = (368, 156)


def res(path):
    return os.path.join(ROOT, path.replace("res://", ""))


def render(entry):
    world_w, world_h = entry["size"][0] // 2, entry["size"][1] // 2
    bg = Image.open(res(entry["bg"])).convert("RGBA")
    k = max(world_w / bg.width, world_h / bg.height)
    bg = bg.resize((round(bg.width * k), round(bg.height * k)), Image.LANCZOS)
    canvas = Image.new("RGBA", (world_w, world_h))
    canvas.alpha_composite(bg.crop((0, 0, world_w, world_h)))
    shade = Image.new("RGBA", canvas.size, (13, 20, 41, round(255 * float(entry.get("dim", 0.12)))))
    canvas.alpha_composite(shade)
    top, bottom = world_h, 0
    for piece in entry["terrain"]:
        art = Image.open(res(piece["art"])).convert("RGBA")
        if piece.get("flip"):
            art = art.transpose(Image.FLIP_LEFT_RIGHT)
        x, y = round(piece["x"] / 2), round(piece["y"] / 2)
        canvas.alpha_composite(art, (x, y))
        top, bottom = min(top, y), max(bottom, y + art.height)
    # Band around the ground with the thumbnail's aspect ratio.
    band_h = round(world_w * SIZE[1] / SIZE[0])
    center = (top - 40 + bottom) // 2
    y0 = max(0, min(world_h - band_h, center - band_h // 2))
    return canvas.crop((0, y0, world_w, y0 + band_h)).resize(SIZE, Image.LANCZOS)


def main():
    os.makedirs(OUT, exist_ok=True)
    maps = json.load(open(os.path.join(ROOT, "shared", "balance", "combat.json"), encoding="utf-8"))["maps"]
    for entry in maps:
        if entry.get("terrain"):
            render(entry).save(os.path.join(OUT, entry["id"] + ".png"))
            print(entry["id"])


if __name__ == "__main__":
    main()
