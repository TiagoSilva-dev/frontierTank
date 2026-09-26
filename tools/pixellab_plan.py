#!/usr/bin/env python3
"""The PixelLab plan: every asset still drawn by code and the art that replaces it.

assets/pixellab_plan.json lists one job per output file: the PixelLab MCP tool to call,
its prompt and size, the file the game already looks for (the loaders fall back to the
code-drawn version while the file is missing) and how to post-process it.

Usage:
  python tools/pixellab_plan.py            status: done / missing per group
  python tools/pixellab_plan.py --missing  the jobs still to generate, one per line
  python tools/pixellab_plan.py --write    rebuild assets/pixellab_plan.json from this file
"""
import hashlib
import json
import os
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
PLAN = os.path.join(ROOT, "assets", "pixellab_plan.json")

# The look the user asked for (reference images of 26/09/2026): a polished, rounded
# "Mochila" window (thick rounded borders, gold trims, inner bevel, soft shadows) and a
# fighting-game super in five beats (full bar, cut-in with a big portrait and title,
# magic circle charge, aim and fire, epic impact with a huge damage number).
STYLE = ("high quality pixel art, warm fantasy adventure game, clean single colour outline, "
         "rounded shapes, gold trims, soft shading, vibrant")

FRAMES = {
    "wood": ("main window frame, warm polished wood with rounded corners, thick gold trim and small gold corner ornaments, inner bevel", 96, 30),
    "wood_dark": ("top bar frame, dark walnut wood, rounded corners, thin gold trim", 72, 24),
    "paper": ("inner parchment panel, cream paper with soft rounded corners and a thin brown border", 72, 22),
    "card": ("item card, light cream with rounded corners, orange rim, glossy top", 64, 18),
    "card_hover": ("item card highlighted, bright cream with white rim and warm glow, rounded corners", 64, 18),
    "card_busy": ("item card greyed out, muted beige, rounded corners", 64, 18),
    "slot": ("recessed inventory slot, dark brown inset with rounded corners and a thin gold rim", 48, 12),
    "slot_light": ("recessed inventory slot on parchment, light inset, rounded corners, thin brown rim", 48, 12),
    "dark": ("dark translucent info box, rounded corners, thin bronze border", 48, 12),
    "glass": ("tooltip box, dark glass with rounded corners and thin bronze border", 48, 12),
    "button": ("orange game button, pill shaped, glossy top highlight, dark outline", 48, 10),
    "button_hover": ("orange game button hovered, brighter, white rim, pill shaped, glossy", 48, 10),
    "button_pressed": ("orange game button pressed in, darker, pill shaped", 48, 10),
    "button_disabled": ("grey game button disabled, flat, pill shaped", 48, 10),
    "button_green": ("green game button, pill shaped, glossy top highlight, dark outline", 48, 10),
    "button_blue": ("blue game button, pill shaped, glossy top highlight, dark outline", 48, 10),
    "button_red": ("red game button, pill shaped, glossy top highlight, dark outline", 48, 10),
    "tab": ("inactive tab, brown wood, rounded top corners", 48, 10),
    "tab_active": ("active tab, glossy orange, rounded top corners, gold rim", 48, 10),
    "plate": ("name plate ribbon, reddish wood with gold rim, rounded", 48, 10),
    "banner": ("red banner ribbon with light rim, rounded", 48, 10),
    "badge": ("small blue level badge, rounded, light rim", 32, 8),
    "badge_gold": ("small gold badge, rounded, bright rim", 32, 8),
}

SKINS = ["base_m", "base_f", "nilo", "lia", "bot_ruivo", "bot_pirata", "bot_maga", "bot_ninja", "bot_robo",
         "bot_princesa", "roupa_capitao", "roupa_maga", "roupa_marinheira", "roupa_ninja", "roupa_princesa", "roupa_samurai"]

ABILITIES = {
    "sting": "a glowing golden stinger bolt hitting, sparks", "feathers": "a volley of sharp feathers slashing",
    "claw": "three icy claw slashes", "spear": "a spear of sunlight falling from the sky and striking the ground",
    "spear_fire": "a flaming spear falling from the sky, fire shockwave", "beam": "a vertical beam of sunlight from the sky",
    "sun_meteor": "a burning sun meteor crashing down, big fiery explosion", "rock_meteor": "a molten rock meteor crashing down, rocks flying",
    "ice_meteor": "a block of ice crashing down and shattering", "fire_pillar": "a pillar of fire erupting from the ground",
    "quake": "the ground cracking and rocks bursting up", "avalanche": "an avalanche of snow and ice chunks",
    "frost_breath": "a cone of freezing breath with ice crystals", "gust": "a slicing wind gust, white arcs",
    "ice_spikes": "ice spikes bursting out of the ground", "chain_lightning": "a lightning bolt strike with electric sparks",
    "chain_fire": "a whip of magenta fire striking", "drain": "dark magenta life energy being drained away",
    "ember_rain": "a rain of embers falling and burning", "blizzard": "a blizzard of snowflakes and ice shards",
    "storm": "a storm cloud with lightning striking down", "mask_storm": "a whirl of flaming masks and pink fire",
}

CURRENCIES = {
    "brasa": "a glowing ember coin", "coroa": "a small golden crown token", "estrela": "a shining star token",
    "tormenta": "a storm orb with lightning inside", "solar": "a radiant sun coin", "eclipse": "an eclipse medallion, dark disc with golden corona",
    "espelho": "a sky mirror gem, blue reflective crystal",
}

AURAS = {"azul": "blue", "roxa": "purple", "verde": "green", "vermelha": "red"}
AURA_LAYERS = {"disc": "soft glowing disc", "ring": "rune ring", "rays": "radiant rays", "star": "six pointed magic star"}


def jobs():
    out = []
    for kind, (what, size, margin) in FRAMES.items():
        out.append({"group": "ui_frames", "file": f"assets/ui/frames/{kind}.png", "tool": "create_ui_asset",
                    "prompt": f"{what}, 9-slice game UI frame, empty centre, transparent background, {STYLE}",
                    "size": [size, size], "post": f"9-slice margin {margin}px: add \"{kind}\": {{\"margin\": {margin}}} to assets/ui/frames/frames.json",
                    "replaces": f"UiKit.drawn_frame(\"{kind}\")"})
    for skin in SKINS:
        out.append({"group": "portraits", "file": f"assets/portraits/{skin}.png", "tool": "create_image_pro",
                    "prompt": f"fighting game super move cut-in portrait of this chibi character, waist up, heroic determined pose, dynamic angle, facing right, transparent background, {STYLE}",
                    "reference": f"assets/characters/{skin}/south.png", "size": [256, 320],
                    "post": "keep transparency; faces right (the rival side mirrors it)", "replaces": "PowCutIn standing AvatarView"})
    for fx, what in ABILITIES.items():
        out.append({"group": "ability_fx", "file": f"assets/effects/abilities/{fx}/frame_00.png", "tool": "create_object_pro_flash + animate_object",
                    "prompt": f"{what}, side view game effect animation, 8-12 frames, transparent background, {STYLE}",
                    "size": [128, 128], "post": "frames as frame_00.png, frame_01.png... (impact at the bottom centre)", "replaces": f"AbilityFx procedural \"{fx}\""})
    for coin, what in CURRENCIES.items():
        out.append({"group": "currency", "file": f"assets/items/currency/{coin}.png", "tool": "create_image_pixflux",
                    "prompt": f"{what}, inventory icon, transparent background, {STYLE}", "size": [32, 32],
                    "post": "32x32, replaces the file drawn by tools/currency_icons.py", "replaces": "tools/currency_icons.py"})
    for colour, name in AURAS.items():
        for layer, what in AURA_LAYERS.items():
            out.append({"group": "auras", "file": f"assets/effects/aura/{colour}_{layer}.png", "tool": "create_image_pro",
                        "prompt": f"{name} {what} of a magic circle seen from the front, glowing light, transparent background, {STYLE}",
                        "size": [256, 256], "post": "centred, additive-friendly (dark = transparent)", "replaces": "tools/aura_textures.py"})
    for icon, what in {"male": "male symbol", "female": "female symbol", "up": "up arrow", "down": "down arrow", "vip": "VIP gold badge"}.items():
        out.append({"group": "icons", "file": f"assets/ui/icons/{icon}.png", "tool": "create_image_pixflux",
                    "prompt": f"{what} game UI icon, transparent background, {STYLE}", "size": [32, 32],
                    "post": "PixelIcons.get_icon picks it up", "replaces": f"PixelIcons procedural \"{icon}\""})
    tiers = {1: "steel blue finish with a blue glow (+9)", 2: "violet crystal finish with a purple glow (+10)", 3: "gold finish with a red glow and sparkles (+12)"}
    with open(os.path.join(ROOT, "shared", "balance", "items.json"), encoding="utf-8") as handle:
        weapons = [w["id"] for w in json.load(handle)["weapons"]]
    for weapon in weapons:
        for tier, what in tiers.items():
            out.append({"group": "weapon_tiers", "file": f"assets/weapons/{weapon}/tier{tier}.png", "tool": "create_image_pro_flash",
                        "prompt": f"the same weapon, same shape and pose, evolved: {what}, transparent background, {STYLE}",
                        "reference": f"assets/weapons/{weapon}/tier0.png", "size": [96, 96],
                        "post": "must keep tier0's silhouette (0.5 img2img drifted; keep the recolour if it still does)", "replaces": "tools/weapon_tiers.py"})
    out.append({"group": "misc", "file": "assets/effects/tombstone.png", "tool": "create_image_pixflux",
                "prompt": f"small cartoon tombstone with a cross, side view, transparent background, {STYLE}", "size": [32, 32],
                "post": "TankFighter._draw draws it when present", "replaces": "TankFighter._draw tombstone rectangles"})
    return out


def digest(path):
    with open(path, "rb") as handle:
        return hashlib.sha256(handle.read()).hexdigest()


def done(job):
    # A file drawn by one of our scripts sits at the same path: it counts as done only
    # once it differs from the code-made one recorded when the plan was written.
    path = os.path.join(ROOT, job["file"])
    return os.path.exists(path) and digest(path) != job.get("code_sha")


def main(args):
    if "--write" in args or not os.path.exists(PLAN):
        listed = jobs()
        for job in listed:
            path = os.path.join(ROOT, job["file"])
            if os.path.exists(path):
                job["code_sha"] = digest(path)
        with open(PLAN, "w", encoding="utf-8") as handle:
            json.dump({"style": STYLE, "jobs": listed}, handle, ensure_ascii=False, indent=1)
            handle.write("\n")
        print("wrote", os.path.relpath(PLAN, ROOT))
    with open(PLAN, encoding="utf-8") as handle:
        plan = json.load(handle)
    groups = {}
    for job in plan["jobs"]:
        finished = done(job)
        entry = groups.setdefault(job["group"], [0, 0])
        entry[0 if finished else 1] += 1
        if "--missing" in args and not finished:
            print(f"{job['group']:<11} {job['file']}  [{job['tool']} {job['size'][0]}x{job['size'][1]}]")
    if "--missing" not in args:
        for group, (finished, missing) in groups.items():
            print(f"{group:<11} {finished:>3} done  {missing:>3} missing")


if __name__ == "__main__":
    main(sys.argv[1:])
