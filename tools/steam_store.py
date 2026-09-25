#!/usr/bin/env python3
"""Art and lists for the Steam store page (launch checklist: the "coming soon" page).

Everything goes to store/steam/ (ignored by Godot, left out of the game package).

Usage:
  python tools/steam_store.py capsules       every capsule size Steamworks asks for, from
                                             the title art (assets/title) scaled by whole
                                             numbers so the pixels stay square
  python tools/steam_store.py achievements   256x256 icons (unlocked and locked) and
                                             achievements.csv to register them on
                                             Steamworks, from shared/balance/achievements.json
  python tools/steam_store.py screenshots    screenshots in Portuguese and English (runs the
                                             game's --screen captures; on Linux without a
                                             display it uses xvfb-run)
  python tools/steam_store.py all

Needs Pillow (pip install pillow); screenshots need Godot (GODOT_BIN or godot on PATH).
"""
import csv
import json
import os
import shutil
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageOps

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "store", "steam")
BG = os.path.join(ROOT, "assets", "title", "title_bg.png")
LOGO = os.path.join(ROOT, "assets", "title", "logo.png")

# name: (size, background scale, crop center (0..1 of the scaled art), logo scale,
# logo center (0..1 of the capsule)). Logo scale 0 = no logo (Steam asks for art only on
# the library hero and the page background).
CAPSULES = {
    "header_capsule": ((920, 430), 2, (0.64, 0.60), 2, (0.36, 0.42)),
    "small_capsule": ((462, 174), 1, (0.5, 0.40), 1, (0.5, 0.46)),
    "main_capsule": ((1232, 706), 2, (0.5, 0.5), 3, (0.40, 0.36)),
    "vertical_capsule": ((748, 896), 3, (0.82, 0.55), 2, (0.5, 0.20)),
    "page_background": ((1438, 810), 3, (0.5, 0.5), 0, None),
    "library_capsule": ((600, 900), 3, (0.86, 0.52), 2, (0.5, 0.17)),
    "library_header": ((920, 430), 2, (0.64, 0.60), 2, (0.36, 0.42)),
    "library_hero": ((3840, 1240), 6, (0.5, 0.45), 0, None),
}


def scaled(path, factor):
    image = Image.open(path).convert("RGBA")
    return image.resize((image.width * factor, image.height * factor), Image.NEAREST)


def crop_center(image, size, center):
    width, height = size
    if image.width < width or image.height < height:
        raise ValueError(f"art {image.size} too small for {size}")
    left = min(max(0, round(image.width * center[0] - width / 2)), image.width - width)
    top = min(max(0, round(image.height * center[1] - height / 2)), image.height - height)
    return image.crop((left, top, left + width, top + height))


def with_logo(canvas, factor, center):
    logo = scaled(LOGO, factor)
    x = round(canvas.width * center[0] - logo.width / 2)
    y = round(canvas.height * center[1] - logo.height / 2)
    # A soft shadow under the logo keeps it readable on the busy art.
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    alpha = logo.split()[3].point(lambda a: 150 if a > 0 else 0)
    shadow.paste((20, 10, 4, 255), (x + factor * 2, y + factor * 3), alpha)
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(factor * 3)))
    canvas.alpha_composite(logo, (x, y))
    return canvas


def cmd_capsules():
    folder = os.path.join(OUT, "capsules")
    os.makedirs(folder, exist_ok=True)
    for name, (size, factor, center, logo_factor, logo_center) in CAPSULES.items():
        canvas = crop_center(scaled(BG, factor), size, center)
        if logo_factor:
            canvas = with_logo(canvas, logo_factor, logo_center)
        canvas.convert("RGB").save(os.path.join(folder, name + ".png"))
        print(f"  {name}.png {size[0]}x{size[1]}")
    # Library logo: the logo alone on transparency (1280x720 at most).
    scaled(LOGO, 5).save(os.path.join(folder, "library_logo.png"))
    print("  library_logo.png 1280x720 (transparent)")
    # Community icon (184x184) and the small client icon (32x32): the cannon emblem.
    emblem = Image.open(LOGO).convert("RGBA").crop((82, 0, 174, 92))
    icon = Image.new("RGBA", (92, 92), (38, 20, 8, 255))
    icon.alpha_composite(emblem)
    icon.resize((184, 184), Image.NEAREST).convert("RGB").save(os.path.join(folder, "community_icon.jpg"), quality=95)
    icon.resize((32, 32), Image.LANCZOS).save(os.path.join(folder, "client_icon.png"))
    print("  community_icon.jpg 184x184, client_icon.png 32x32")


def res_path(path):
    return os.path.join(ROOT, path.replace("res://", "")) if path.startswith("res://") else path


def achievement_icon(source, locked):
    art = Image.open(source).convert("RGBA")
    box = art.getbbox() or (0, 0, art.width, art.height)
    art = art.crop(box)
    # Whole-number scale into the 176px inner square.
    factor = max(1, min(176 // art.width, 176 // art.height))
    art = art.resize((art.width * factor, art.height * factor), Image.NEAREST)
    if art.width > 176 or art.height > 176:
        art.thumbnail((176, 176), Image.LANCZOS)
    tile = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    draw = ImageDraw.Draw(tile)
    draw.rounded_rectangle((4, 4, 251, 251), radius=28, fill=(122, 66, 24, 255), outline=(42, 22, 8, 255), width=8)
    draw.rounded_rectangle((20, 20, 235, 235), radius=18, fill=(251, 233, 191, 255), outline=(224, 162, 74, 255), width=6)
    tile.alpha_composite(art, ((256 - art.width) // 2, (256 - art.height) // 2))
    if locked:
        gray = ImageOps.grayscale(tile.convert("RGB")).point(lambda v: int(v * 0.55))
        tile = Image.merge("RGBA", (gray, gray, gray, tile.split()[3]))
    return tile


def english_names():
    names = {}
    msgid = None
    for line in open(os.path.join(ROOT, "locale", "en.po"), encoding="utf-8"):
        if line.startswith("msgid "):
            msgid = json.loads(line[6:])
        elif line.startswith("msgstr ") and msgid is not None:
            names[msgid] = json.loads(line[7:])
            msgid = None
    return names


def cmd_achievements():
    folder = os.path.join(OUT, "achievements")
    os.makedirs(folder, exist_ok=True)
    data = json.load(open(os.path.join(ROOT, "shared", "balance", "achievements.json"), encoding="utf-8"))
    english = english_names()
    rows = []
    for entry in data["achievements"]:
        source = res_path(entry["icon"])
        achievement_icon(source, False).save(os.path.join(folder, entry["id"] + ".png"))
        achievement_icon(source, True).save(os.path.join(folder, entry["id"] + "_locked.png"))
        rows.append([entry["id"], entry["name"], english.get(entry["name"], ""), entry["desc"], english.get(entry["desc"], ""), entry["id"] + ".png", entry["id"] + "_locked.png"])
    with open(os.path.join(folder, "achievements.csv"), "w", newline="", encoding="utf-8") as out:
        writer = csv.writer(out, lineterminator="\n")
        writer.writerow(["api_name", "name_ptbr", "name_en", "desc_ptbr", "desc_en", "icon", "icon_locked"])
        writer.writerows(rows)
    print(f"  {len(rows)} achievements, icons and achievements.csv in {folder}")


SCREENS = [
    ("01_battle", ["--screen=battle", "--demo=1", "--zoom=1.25"]),
    ("02_pow", ["--screen=battle", "--demo=1", "--auto=1", "--frames=240"]),
    ("03_instance", ["--screen=pve_battle", "--demo=1", "--instance=picos_gelados", "--level=10", "--phase=3"]),
    ("04_city", ["--screen=city", "--demo=1"]),
    ("05_bag", ["--screen=bag", "--demo=1"]),
    ("06_smith", ["--screen=smith", "--demo=1", "--tab=Moedas"]),
    ("07_shop", ["--screen=shop", "--demo=1"]),
    ("08_cards", ["--screen=cards", "--demo=1"]),
]


def cmd_screenshots():
    godot = os.environ.get("GODOT_BIN") or shutil.which("godot") or shutil.which("godot4")
    if not godot:
        sys.exit("Godot not found: set GODOT_BIN.")
    prefix = []
    if sys.platform.startswith("linux") and not os.environ.get("DISPLAY") and shutil.which("xvfb-run"):
        prefix = ["xvfb-run", "-a", "-s", "-screen 0 1280x720x24"]
    for lang in ["pt_BR", "en"]:
        folder = os.path.join(OUT, "screenshots", "pt" if lang == "pt_BR" else "en")
        os.makedirs(folder, exist_ok=True)
        for name, args in SCREENS:
            out = os.path.join(folder, name + ".png")
            command = prefix + [godot, "--path", ROOT, "--rendering-driver", "opengl3", "--", *args, f"--lang={lang}", f"--out={out}", "--profile=user://store_capture.json"]
            subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=180)
            print(("  " if os.path.exists(out) else "  FAILED ") + os.path.relpath(out, ROOT))


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else "all"
    os.makedirs(OUT, exist_ok=True)
    # Godot must not import the store art into the game.
    open(os.path.join(ROOT, "store", ".gdignore"), "a").close()
    commands = {"capsules": [cmd_capsules], "achievements": [cmd_achievements], "screenshots": [cmd_screenshots], "all": [cmd_capsules, cmd_achievements, cmd_screenshots]}
    if command not in commands:
        sys.exit(__doc__)
    for run in commands[command]:
        run()


if __name__ == "__main__":
    main()
