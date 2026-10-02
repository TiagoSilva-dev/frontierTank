#!/usr/bin/env python3
"""Builds the art of the top-down Caçada field (0.21 pilot) from PixelLab downloads.

  field_assets.py units   download every unit's character pack and write
                          assets/field/units/<id>.png (see client/ui/field_sprites.gd for the layout)
  field_assets.py tiles [zone]   write assets/field/<zone>/tiles.json + tilesheets from the Wang sets
  field_assets.py fx      hue-shift the three fire effects into one set per element
                          (assets/field/fx/<style>_<element>.png)
  field_assets.py all

Needs Pillow (a venv is fine). Characters and tilesets are the ids PixelLab returned; jobs of
other days expire, so the results are kept in assets/field.
"""
import colorsys
import io
import json
import sys
import urllib.request
import zipfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent / "assets" / "field"
CELL = 64
FRAMES = 8
DIRS = ["south", "south-east", "east", "north-east", "north", "north-west", "west", "south-west"]
WALK = ["south", "north", "east", "west"]

UNITS = {
    "escaravelho_solar": "1c61a200-a767-4670-882b-8a44f0f2a330",
    "chacal_ambar": "45d51d83-c8a1-4994-91a0-5d0580286d09",
    "leao_dourado": "fb040ad2-0082-4ef0-90f5-f972fb88793a",
    "fenix_dourada": "53ecf702-a653-414c-b5b3-7efc0b8703e6",
    "trainer": "e630bdb9-7137-4e1b-bd4e-fc7041b579fd",
    "pinguim_cristal": "57ef1ee6-736f-4e50-b567-01503ca97a8f",
    "coelho_neve": "2f66b8f2-a88e-4a7a-8c8d-c48b9850640d",
    "raposa_glacial": "fac6e278-9e2c-403c-b8e4-e8c50bb3b935",
    "lobo_boreal": "43260ef3-9239-4ede-a35c-56e01af70b96",
}

ZONES = {
    "sol": {
        "stone": "b38d3217-a327-402c-b61a-912215de9bb6",
        "water": "76632a30-db72-49ae-bdc3-785780d33c49",
        "stone_blocks": [[3, 3, 7, 4], [39, 21, 6, 5], [2, 23, 5, 4]],
        "ponds": [[41, 7, 5.0, 3.5], [8, 15, 3.0, 2.2]],
        "decor": [
            {"png": "acacia.png", "count": 30, "scale": 1.0},
            {"png": "palm.png", "count": 16, "scale": 1.0},
            {"png": "ruin.png", "count": 8, "scale": 1.0},
            {"png": "bush.png", "count": 46, "scale": 1.0},
            {"png": "rocks.png", "count": 26, "scale": 0.9, "cover": True},
            {"png": "tuft.png", "count": 140, "scale": 1.1, "cover": True},
        ],
    },
    "gelo": {
        "stone": "e24ee36d-4fc5-4332-92e7-43b48a3c2c8a",
        "water": "8df70978-4535-4155-b007-a962ca82a7e6",
        "shade": [0.80, 0.88, 0.97],
        "stone_blocks": [[4, 20, 7, 4], [38, 3, 6, 5], [22, 1, 5, 3], [33, 19, 4, 3]],
        "ponds": [[8, 7, 4.0, 3.0], [41, 23, 5.0, 3.2], [13, 22, 3.0, 2.0]],
        "decor": [
            {"png": "pine.png", "count": 34, "scale": 1.0},
            {"png": "birch.png", "count": 14, "scale": 1.0},
            {"png": "ruin.png", "count": 8, "scale": 1.0},
            {"png": "bush.png", "count": 40, "scale": 1.0},
            {"png": "rocks.png", "count": 26, "scale": 0.9, "cover": True},
            {"png": "tuft.png", "count": 140, "scale": 1.1, "cover": True},
        ],
    },
}


# Hue (degrees) the orange fire effects are turned to for each element, and how much the
# saturation is kept: ice is pale cyan, masks violet, sky electric yellow, runes green.
FX_HUES = {"gelo": (192, 0.8), "mascara": (282, 0.95), "ceu": (52, 1.0), "viking": (140, 0.85)}
FX_STYLES = ("bolt", "orb", "slash")


def shift_hue(image: Image.Image, degrees: float, keep: float) -> Image.Image:
    image = image.convert("RGBA")
    pixels = image.load()
    for y in range(image.height):
        for x in range(image.width):
            r, g, b, a = pixels[x, y]
            if a == 0:
                continue
            h, sat, val = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
            # Orange sits near 30 degrees: move it so that the shift lands on `degrees`.
            h = ((degrees - 30.0) / 360.0 + h) % 1.0
            sat = min(1.0, sat * keep)
            red, green, blue = colorsys.hsv_to_rgb(h, sat, val)
            pixels[x, y] = (round(red * 255), round(green * 255), round(blue * 255), a)
    return image


def build_fx() -> None:
    for element, (degrees, keep) in FX_HUES.items():
        for style in FX_STYLES:
            source = Image.open(ROOT / "fx" / f"{style}.png")
            target = ROOT / "fx" / f"{style}_{element}.png"
            shift_hue(source, degrees, keep).save(target)
            print(target.name)


def fetch(url: str) -> bytes:
    with urllib.request.urlopen(url) as response:
        return response.read()


def build_unit(unit: str, character: str) -> None:
    pack = zipfile.ZipFile(io.BytesIO(fetch(f"https://api.pixellab.ai/mcp/characters/{character}/download")))
    meta = json.loads(pack.read("metadata.json"))
    frames = meta["states"][0]["frames"]
    sheet = Image.new("RGBA", (CELL * FRAMES, CELL * 5), (0, 0, 0, 0))
    for column, direction in enumerate(DIRS):
        picture = Image.open(io.BytesIO(pack.read(frames["rotations"][direction]))).convert("RGBA")
        sheet.paste(picture, (column * CELL, 0))
    walk = frames.get("animations", {}).get("walk", {})
    for row, direction in enumerate(WALK, start=1):
        names = walk.get(direction)
        if not names:
            # No cycle yet: show the resting picture instead of a hole.
            picture = Image.open(io.BytesIO(pack.read(frames["rotations"][direction]))).convert("RGBA")
            names = None
        for column in range(FRAMES):
            if names:
                # frame 0 is the reference pose; the cycle is the generated frames after it.
                index = 1 + column if len(names) > FRAMES else column
                picture = Image.open(io.BytesIO(pack.read(names[index]))).convert("RGBA")
            sheet.paste(picture, (column * CELL, row * CELL))
    target = ROOT / "units" / f"{unit}.png"
    target.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(target)
    print(unit, "walk" if walk else "NO WALK", target)


def build_tiles(zone: str, config: dict) -> None:
    folder = ROOT / zone
    folder.mkdir(parents=True, exist_ok=True)
    sets = {}
    for kind in ("stone", "water"):
        tileset = config[kind]
        sheet = fetch(f"https://api.pixellab.ai/mcp/tilesets/{tileset}/image?inline=true")
        (folder / f"{kind}.png").write_bytes(sheet)
        meta = json.loads(fetch(f"https://api.pixellab.ai/mcp/tilesets/{tileset}/metadata"))
        tiles = []
        for tile in meta["tileset_data"]["tiles"]:
            corners = tile["corners"]
            box = tile["bounding_box"]
            tiles.append([int(corners[c] == "upper") for c in ("NW", "NE", "SW", "SE")] + [box["x"], box["y"]])
        sets[kind] = {"png": f"{kind}.png", "tiles": tiles}
    data = {
        "order": ["stone", "water"],
        "sets": sets,
        "stone_blocks": config["stone_blocks"],
        "ponds": config["ponds"],
        "decor": config["decor"],
    }
    if "shade" in config:
        data["shade"] = config["shade"]
    (folder / "tiles.json").write_text(json.dumps(data, separators=(",", ":")))
    print(zone, "tiles", {k: len(v["tiles"]) for k, v in sets.items()})


def main() -> None:
    what = sys.argv[1] if len(sys.argv) > 1 else "all"
    only = sys.argv[2] if len(sys.argv) > 2 else None
    if what in ("units", "all"):
        for unit, character in UNITS.items():
            if only and unit != only:
                continue
            try:
                build_unit(unit, character)
            except Exception as error:  # a unit still generating must not stop the others
                print(unit, "FAILED", error)
    if what in ("fx", "all"):
        build_fx()
    if what in ("tiles", "all"):
        for zone, config in ZONES.items():
            if only and zone != only:
                continue
            build_tiles(zone, config)


if __name__ == "__main__":
    main()
