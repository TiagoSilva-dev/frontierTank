#!/usr/bin/env python3
"""Installs the art of the PvE gear (0.31) from the PixelLab originals in tools/gear_src.

Every piece is one PNG per view, exactly as PixelLab drew it (recipes and seeds are in
docs/PIXELLAB_GEAR.md). This tool turns them into what the game reads:

  camisa, calca, anel, amuleto  assets/cosmetics/<id>/icon.png (the original, 96x96)
  chapeu, oculos                front.png (the icon and the part worn in the menus) and side.png
                                (worn lying down in battle), both cropped to their opaque pixels,
                                plus the entry in assets/cosmetics/fit.json
  asas                          wing.png (ONE wing, root at `root` in items.json), side.png (the
                                same wing), front.png (the pair, mirrored around the roots) and
                                icon.png (64 px wide)

Run it again whenever a source changes; it only rewrites the pieces listed here. Needs Pillow:
    python tools/gear_art.py [--only <id> ...]
"""
import json
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "tools" / "gear_src"
COSMETICS = ROOT / "assets" / "cosmetics"
ITEMS = ROOT / "shared" / "balance" / "items.json"

ICONS = ["camisa_couro", "camisa_aco_azul", "camisa_arcana", "camisa_dragao",
         "calca_couro", "calca_aco_azul", "calca_arcana", "calca_dragao",
         "anel_ferro", "anel_cobalto", "anel_arcano", "anel_dragao",
         "amuleto_osso", "amuleto_safira", "amuleto_arcano", "amuleto_dragao"]
HATS = ["chapeu_couro", "chapeu_aco_azul", "chapeu_arcano", "chapeu_dragao"]
GLASSES = ["oculos_aviador", "oculos_cristal", "oculos_arcano", "oculos_dragao"]
WINGS = ["asas_pardal", "asas_cristal", "asas_arcanas", "asas_dragao"]

# How each piece is worn (see LookRig.fit_for): `width` = head widths the art spans, `drop` = how far
# down the head the base rests (hats) or a shift from the eye line (glasses), `dx` = a shift towards
# where the character faces. The images are cropped to their pixels, so the crop is the whole art.
FIT = {
    "chapeu_couro": {"front": {"width": 1.05, "drop": 0.30}, "side": {"width": 0.95, "drop": 0.30, "dx": -0.04}},
    "chapeu_aco_azul": {"front": {"width": 1.1, "drop": 0.34}, "side": {"width": 1.0, "drop": 0.36, "dx": -0.03}},
    "chapeu_arcano": {"front": {"width": 1.45, "drop": 0.26}, "side": {"width": 1.3, "drop": 0.26, "dx": -0.04}},
    "chapeu_dragao": {"front": {"width": 1.35, "drop": 0.36}, "side": {"width": 1.2, "drop": 0.38, "dx": -0.04}},
    "oculos_aviador": {"front": {"width": 0.7}, "side": {"width": 0.36, "dx": 0.0, "drop": 0.0}},
    "oculos_cristal": {"front": {"width": 0.7}, "side": {"width": 0.36, "dx": 0.0, "drop": 0.0}},
    "oculos_arcano": {"front": {"width": 0.62}, "side": {"width": 0.38, "dx": 0.0, "drop": 0.0}},
    "oculos_dragao": {"front": {"width": 0.74}, "side": {"width": 0.38, "dx": 0.0, "drop": 0.0}},
}


def cropped(image: Image.Image, pad: int = 1) -> Image.Image:
    box = image.getbbox()
    if box is None:
        return image
    left, top, right, bottom = box
    box = (max(0, left - pad), max(0, top - pad), min(image.width, right + pad), min(image.height, bottom + pad))
    return image.crop(box)


def load(name: str) -> Image.Image:
    return Image.open(SRC / f"{name}.png").convert("RGBA")


def save(image: Image.Image, folder: str, view: str) -> None:
    target = COSMETICS / folder
    target.mkdir(parents=True, exist_ok=True)
    image.save(target / f"{view}.png")
    print(f"  {folder}/{view}.png {image.size}")


def wing_pair(wing: Image.Image, root: tuple) -> Image.Image:
    """The pair of wings for menus: the original on the left of the roots, its mirror on the right."""
    width, height = wing.size
    mirrored = wing.transpose(Image.FLIP_LEFT_RIGHT)
    canvas = Image.new("RGBA", (width * 2, height), (0, 0, 0, 0))
    canvas.alpha_composite(wing, (width - root[0], 0))
    canvas.alpha_composite(mirrored, (root[0], 0))
    return cropped(canvas, 0)


def install_wing(item_id: str, roots: dict) -> None:
    root = roots[item_id]
    wing = load(item_id)
    save(wing, item_id, "wing")
    save(wing, item_id, "side")
    pair = wing_pair(wing, root)
    save(pair, item_id, "front")
    icon_width = 64
    icon = pair.resize((icon_width, max(1, round(pair.height * icon_width / pair.width))), Image.LANCZOS)
    save(icon, item_id, "icon")


def fit_text(fit: dict) -> str:
    """fit.json as the game's own file is written: hats on two lines, glasses on one."""
    lines = []
    for key, entry in fit.items():
        views = [(view, json.dumps(entry[view], separators=(", ", ": "))) for view in ("front", "side")]
        if "crop" in entry["front"]:
            lines.append(f'  "{key}": {{\n    "front": {views[0][1]},\n    "side": {views[1][1]}\n  }}')
        else:
            lines.append(f'  "{key}": {{"front": {views[0][1]}, "side": {views[1][1]}}}')
    return "{\n" + ",\n".join(lines) + "\n}\n"


def main() -> None:
    only = sys.argv[sys.argv.index("--only") + 1:] if "--only" in sys.argv else []
    wanted = lambda item_id: not only or item_id in only
    items = json.loads(ITEMS.read_text(encoding="utf-8"))
    roots = {d["id"]: d["root"] for d in items["cosmetics"] if d.get("slot") == "asas"}
    for item_id in ICONS:
        if wanted(item_id):
            save(load(item_id), item_id, "icon")
    fit_path = COSMETICS / "fit.json"
    fit = json.loads(fit_path.read_text(encoding="utf-8"))
    for item_id in HATS + GLASSES:
        if not wanted(item_id):
            continue
        save(cropped(load(item_id)), item_id, "front")
        save(cropped(load(item_id + "_side")), item_id, "side")
        fit[item_id] = FIT[item_id]
    fit_path.write_text(fit_text(fit), encoding="utf-8")
    for item_id in WINGS:
        if wanted(item_id):
            install_wing(item_id, roots)


if __name__ == "__main__":
    main()
