#!/usr/bin/env python3
"""Builds the art of the top-down Caçada field (0.21 pilot) from PixelLab downloads.

  field_assets.py units   download every unit's character pack and write
                          assets/field/units/<id>.png (see client/ui/field_sprites.gd for the layout)
  field_assets.py tiles [zone]   write assets/field/<zone>/tiles.json + tilesheets from the Wang sets
  field_assets.py decor [zone]   download the scenery objects (DECOR) into assets/field/<zone>/
  field_assets.py recolor [zone]   re-apply RECOLOR (tile sheets) and DERIVED (decor made from another
                          zone's picture) from tools/field_src, offline
  field_assets.py fx      hue-shift the three fire effects into one set per element
                          (assets/field/fx/<style>_<element>.png)
  field_assets.py all

Needs Pillow (a venv is fine). Characters and tilesets are the ids PixelLab returned; jobs of
other days expire, so the results are kept in assets/field.
"""
import colorsys
import io
import json
import shutil
import sys
import urllib.request
import zipfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent / "assets" / "field"
# The sheets exactly as PixelLab returned them: RECOLOR always starts from these, so it can be
# run again after a change of rules.
SOURCES = Path(__file__).resolve().parent / "field_src"
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
    "brasinha": "e9d2aa99-61dc-4b99-8faa-3f1fa8cb8bf3",
    "diabrete_mascarado": "ede270d4-1ada-4fc9-83ed-048ce09c30f4",
    "cao_de_lava": "b1f53bf0-3bfe-413f-8b5d-337ef9a32fad",
    "rei_mascara": "a374a8b2-bab0-499a-a948-d78eaada0760",
    "nuvenzinha": "be05652c-a11d-43f4-a768-2e53a5838f39",
    "passaro_trovao": "91edb435-1cb2-40e5-9446-5b198bd01f71",
    "grifinho": "1d497b79-019c-46bb-947c-c0dd0d806b8c",
    "dragao_tempestade": "286e4811-4962-4cbe-9dfb-2d110c613b67",
    "corvo_runico": "78080e88-265d-4c42-adde-f96287adb463",
    "javali_guerra": "877ac7a5-dcb7-4373-b652-e041e129593e",
    "urso_berserker": "68d55ab8-8579-4b49-8cc6-7b63f47fb79e",
    "lobo_fenrir": "03608ff5-0a6d-42bc-b666-647332b3cf8c",
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
    # 0.22: the three zones that were still on the side arena. The "water" set is lava, a sky
    # lake and cold sea; the "stone" set obsidian slabs, floating marble and rune slate.
    "mascara": {
        "stone": "01787701-d699-4c05-869f-4f02ea1de13f",
        "water": "ae3f3d04-ffdc-42b3-95b6-e1bdec4d1226",
        "ruined": True,
        "stone_blocks": [[3, 3, 7, 4], [39, 19, 6, 5], [24, 24, 5, 3]],
        "ponds": [[42, 6, 4.0, 3.0], [7, 22, 4.5, 3.0], [31, 2.5, 3.0, 1.8]],
        "decor": [
            {"png": "dead_tree.png", "count": 22, "scale": 1.0},
            {"png": "thorn_tree.png", "count": 14, "scale": 1.0},
            {"png": "ruin.png", "count": 3, "scale": 1.0},
            {"png": "ruin.png", "count": 5, "scale": 1.0, "on_stone": True},
            {"png": "bush.png", "count": 34, "scale": 1.0},
            {"png": "rocks.png", "count": 26, "scale": 0.9, "cover": True},
            {"png": "rocks.png", "count": 12, "scale": 0.9, "cover": True, "on_stone": True},
            {"png": "tuft.png", "count": 120, "scale": 1.1, "cover": True},
        ],
    },
    "ceu": {
        "stone": "96245dfc-db37-4a86-a504-42492d8458c8",
        "water": "ac2b5475-2e65-48fd-84de-4f5d70a0ccdc",
        "shade": [0.9, 0.95, 1.0],
        "ruined": True,
        "stone_blocks": [[5, 20, 8, 4], [36, 3, 7, 5], [20, 1, 5, 3]],
        "ponds": [[40, 22, 5.0, 3.2], [9, 6, 4.0, 3.0], [26, 25, 3.0, 2.0]],
        "decor": [
            {"png": "sky_tree.png", "count": 22, "scale": 1.0},
            {"png": "blossom.png", "count": 14, "scale": 1.0},
            {"png": "ruin.png", "count": 3, "scale": 1.0},
            {"png": "ruin.png", "count": 5, "scale": 1.0, "on_stone": True},
            {"png": "bush.png", "count": 34, "scale": 1.0},
            {"png": "rocks.png", "count": 20, "scale": 0.9, "cover": True},
            {"png": "rocks.png", "count": 12, "scale": 0.9, "cover": True, "on_stone": True},
            {"png": "tuft.png", "count": 120, "scale": 1.1, "cover": True},
        ],
    },
    "viking": {
        "stone": "c67d1cd5-1677-4419-a015-c82cf7812516",
        "water": "7c2e9778-4f60-4d30-8d1b-6e9d08aea6b5",
        "ruined": True,
        "stone_blocks": [[4, 4, 6, 4], [37, 20, 7, 4], [22, 25, 4, 3]],
        "ponds": [[42, 5, 5.5, 4.0], [6, 24, 5.0, 3.2], [24, 2, 4.0, 2.0]],
        "decor": [
            {"png": "pine.png", "count": 26, "scale": 1.0},
            {"png": "oak.png", "count": 14, "scale": 1.0},
            {"png": "ruin.png", "count": 3, "scale": 1.0},
            {"png": "ruin.png", "count": 5, "scale": 1.0, "on_stone": True},
            {"png": "bush.png", "count": 34, "scale": 1.0},
            {"png": "rocks.png", "count": 26, "scale": 0.9, "cover": True},
            {"png": "rocks.png", "count": 12, "scale": 0.9, "cover": True, "on_stone": True},
            {"png": "tuft.png", "count": 90, "scale": 1.0, "cover": True},
        ],
    },
}


# Scenery objects (PixelLab map objects, "no ground, no platform, no base"): published name ->
# object id. `field_assets.py decor [zone]` downloads them next to the zone's tiles.json.
DECOR = {
    "mascara": {
        "dead_tree.png": "ecf189c0-e67e-49d2-8508-4b2fc8cce33c",
        "thorn_tree.png": "7f66b068-623d-4661-8054-1f05a8d8634e",
        "ruin.png": "b168af85-4c60-4597-b584-4cd193455dd0",
        "bush.png": "8f34415d-aada-4944-b49e-14841d601077",
        "rocks.png": "5de10331-61b7-4b93-8be2-6e9c949b5826",
        "tuft.png": "79cf7916-75ef-4fab-8e63-00c43ea19ac1",
    },
    "ceu": {
        "sky_tree.png": "b0a45840-d922-48e4-a5bd-8dd9cbca214d",
        "blossom.png": "55ce5272-c3de-4b8f-a630-d83f8daac09e",
        "ruin.png": "89b925d0-e75f-465e-b14e-67bf6cbac1b2",
        "bush.png": "6b57c964-fb64-4542-a8ef-a85fe85a7c5e",
        "rocks.png": "a6383e3e-e0ef-4604-87ee-c2c070ab55ea",
        "tuft.png": "d4b1b1d2-26ef-4ba3-bdd6-e42968478781",
    },
    "viking": {
        "pine.png": "e9fcf44e-7679-456e-b5d5-287d01a225b9",
        "oak.png": "244066c1-efaa-42e8-ba00-f2d909f8448d",
        "ruin.png": "540296d8-2f0c-412b-968a-3deec8790603",
        "bush.png": "5d2aad4c-27ca-4802-8514-6c903e53dc61",
        "rocks.png": "75e55a1f-2a89-4d1c-b396-3d66f92a33b9",
    },
}


# Tile sheets graded after the download (field_assets.py recolor): per pixel, the first rule whose
# hue range (degrees) holds the pixel sets the hue to `to`, then scales saturation and value.
# Brasa came back as a near-black violet ground with teal-grey slabs: the ground is lifted to
# charred earth and the slabs turned to warm basalt, so the zone reads as embers and not as a swamp.
CHARRED = {"hue": (225, 345), "to": 8, "sat": 0.6, "val": 1.9}
RECOLOR = {
    "mascara": {
        # The lava set's own ground has to follow the stone set's, or every pool gets a black halo.
        "stone": [{"hue": (100, 215), "to": 24, "sat": 0.6, "val": 2.3}, CHARRED],
        "water": [CHARRED],
    },
}

# Scenery made from another zone's picture instead of its own generation. The Drakkar tuft came back
# as a cyan crystal that dominated the beach: the dry grass of the sun zone, turned to sea green.
DERIVED = {
    "viking": {
        "tuft.png": {"from": "sol/tuft.png", "rules": [{"hue": (0, 360), "to": 112, "sat": 0.85, "val": 0.7}]},
    },
}


def regrade(image: Image.Image, rules: list) -> Image.Image:
    image = image.convert("RGBA")
    pixels = image.load()
    for y in range(image.height):
        for x in range(image.width):
            r, g, b, a = pixels[x, y]
            if a == 0:
                continue
            h, sat, val = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
            degrees = h * 360.0
            for rule in rules:
                low, high = rule["hue"]
                if low <= degrees < high:
                    h = (rule["to"] if "to" in rule else degrees) / 360.0
                    sat = min(1.0, sat * rule.get("sat", 1.0))
                    val = min(1.0, val * rule.get("val", 1.0))
                    break
            red, green, blue = colorsys.hsv_to_rgb(h, sat, val)
            pixels[x, y] = (round(red * 255), round(green * 255), round(blue * 255), a)
    return image


def build_recolor(only: str | None) -> None:
    for zone, sheets in RECOLOR.items():
        if only and zone != only:
            continue
        for kind, rules in sheets.items():
            source = SOURCES / zone / f"{kind}.png"
            target = ROOT / zone / f"{kind}.png"
            if not source.exists():
                source.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(target, source)
            regrade(Image.open(source), rules).save(target)
            print(zone, kind, "recolored")
    for zone, pictures in DERIVED.items():
        if only and zone != only:
            continue
        for name, spec in pictures.items():
            regrade(Image.open(ROOT / spec["from"]), spec["rules"]).save(ROOT / zone / name)
            print(zone, name, "derived from", spec["from"])


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


def build_decor(zone: str, objects: dict) -> None:
    folder = ROOT / zone
    folder.mkdir(parents=True, exist_ok=True)
    for name, object_id in objects.items():
        data = fetch(f"https://api.pixellab.ai/mcp/map-objects/{object_id}/download")
        picture = Image.open(io.BytesIO(data)).convert("RGBA")
        picture.save(folder / name)
        print(zone, name, picture.size)


def build_tiles(zone: str, config: dict) -> None:
    folder = ROOT / zone
    folder.mkdir(parents=True, exist_ok=True)
    sets = {}
    for kind in ("stone", "water"):
        tileset = config[kind]
        sheet = fetch(f"https://api.pixellab.ai/mcp/tilesets/{tileset}/image?inline=true")
        (folder / f"{kind}.png").write_bytes(sheet)
        if kind in RECOLOR.get(zone, {}):
            (SOURCES / zone).mkdir(parents=True, exist_ok=True)
            (SOURCES / zone / f"{kind}.png").write_bytes(sheet)
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
    if config.get("ruined"):
        data["ruined"] = True
    (folder / "tiles.json").write_text(json.dumps(data, separators=(",", ":")))
    print(zone, "tiles", {k: len(v["tiles"]) for k, v in sets.items()})
    build_recolor(zone)


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
    if what in ("decor", "all"):
        for zone, objects in DECOR.items():
            if only and zone != only:
                continue
            build_decor(zone, objects)
        build_recolor(only)
    if what == "recolor":
        build_recolor(only)
    if what in ("tiles", "all"):
        for zone, config in ZONES.items():
            if only and zone != only:
                continue
            build_tiles(zone, config)


if __name__ == "__main__":
    main()
