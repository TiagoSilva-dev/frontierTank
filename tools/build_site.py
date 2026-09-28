#!/usr/bin/env python3
"""Official website (website/): game data for the wiki, game art and the logo.

The wiki reads everything from the same balance files the game uses
(shared/balance/*.json) and the English names from locale/en.po, so a new weapon,
monster or number shows up on the site after running this again. The pages themselves
(website/*.html, css/, js/) are written by hand.

Usage:  python tools/build_site.py [--no-logo]

Writes:
  website/data/gamedata.js   window.GF_DATA = {...} (works from file:// too)
  website/img/game/...       icons, sprites, map art (lossless, pixels untouched)
  website/img/shots/<lang>/  screenshots from store/steam/screenshots
  website/img/brand/...      the logo (tools/make_logo.py)
  website/fonts/...          the pixel fonts (CC0 / OFL) and their licences
"""
import argparse
import datetime
import json
import os
import re
import shutil
import sys

from PIL import Image

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
SITE = os.path.join(ROOT, "website")
BALANCE = os.path.join(ROOT, "shared", "balance")
IMG = os.path.join(SITE, "img", "game")

sys.path.insert(0, os.path.dirname(__file__))

# Battle ranks shown under the name (client/components/fighter.gd).
RANKS = ["Recruta", "Soldado", "Veterano", "Sargento", "Capitão", "Major", "Coronel", "General", "Marechal"]
ATTR_NAMES = {"ataque": "Ataque", "defesa": "Defesa", "agilidade": "Agilidade", "sorte": "Sorte"}
SLOT_NAMES = {"arma": "Arma", "roupa": "Roupa", "chapeu": "Chapéu", "oculos": "Óculos", "asas": "Asas", "cabelo": "Cabelo"}


# ---------- translations ----------

def load_po(path):
    """msgid -> msgstr from a gettext PO file (multi-line strings joined)."""
    table, key, value, target = {}, None, None, None

    def unquote(text):
        return json.loads(text)

    with open(path, encoding="utf-8") as handle:
        for raw in handle:
            line = raw.strip()
            if line.startswith("msgid "):
                if key is not None and value:
                    table[key] = value
                key, value, target = unquote(line[6:]), "", "id"
            elif line.startswith("msgstr "):
                value, target = unquote(line[7:]), "str"
            elif line.startswith('"') and target:
                if target == "id":
                    key += unquote(line)
                else:
                    value += unquote(line)
            elif not line:
                target = None
    if key is not None and value:
        table[key] = value
    return table


PO = {}


def T(text):
    """A text in both languages: the Portuguese source is the key of the English one."""
    if text is None:
        return None
    text = str(text)
    return {"pt": text, "en": PO.get(text, text)}


# ---------- art ----------

COPIED = set()


def res_to_path(res):
    return os.path.join(ROOT, res.replace("res://", "")) if res.startswith("res://") else os.path.join(ROOT, res)


def art(source, dest, tint=None, crop=False):
    """Copy one image to website/img/game/<dest> and return its site-relative URL."""
    src = res_to_path(source)
    if not os.path.exists(src):
        return None
    out = os.path.join(IMG, dest)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    if tint or crop or not src.endswith(".png"):
        image = Image.open(src).convert("RGBA")
        if crop and image.getbbox():
            image = image.crop(image.getbbox())
        if tint:
            r, g, b = (int(tint[i:i + 2], 16) for i in (0, 2, 4))
            px = image.load()
            for y in range(image.height):
                for x in range(image.width):
                    pr, pg, pb, pa = px[x, y]
                    px[x, y] = (pr * r // 255, pg * g // 255, pb * b // 255, pa)
        image.save(out, optimize=True)
    else:
        shutil.copyfile(src, out)
    COPIED.add(os.path.normpath(out))
    return "img/game/" + dest.replace(os.sep, "/")


def webp(source, dest):
    """Big pictures (map backgrounds, screenshots) as lossless WebP: same pixels, smaller."""
    src = res_to_path(source)
    if not os.path.exists(src):
        return None
    out = os.path.join(SITE, dest)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    Image.open(src).convert("RGB").save(out, "WEBP", lossless=True, quality=100, method=6)
    COPIED.add(os.path.normpath(out))
    return dest.replace(os.sep, "/")


# ---------- data ----------

def load(name):
    with open(os.path.join(BALANCE, name), encoding="utf-8") as handle:
        return json.load(handle)


def game_version():
    with open(os.path.join(ROOT, "client", "net", "net_client.gd"), encoding="utf-8") as handle:
        match = re.search(r'GAME_VERSION: String = "([^"]+)"', handle.read())
    return match.group(1) if match else "?"


def build_data():
    items = load("items.json")
    combat = load("combat.json")
    achievements = load("achievements.json")
    store = load("store.json")

    instances = combat["instances"]
    drops = {}
    for inst in instances:
        for wid in inst["loot"]["weapons"]:
            drops.setdefault(wid, []).append(inst["id"])
        drops.setdefault(inst["loot"]["super"], []).append(inst["id"])

    weapons = []
    for w in items["weapons"]:
        pow_rules = {k: v for k, v in w["pow"].items() if k not in ("name", "desc")}
        proj = w["projectile"]
        proj_src = f"res://assets/projectiles/{proj['sprite']}.png" if proj.get("sprite") != "icon" else f"res://assets/weapons/{w['id']}/tier0.png"
        weapons.append({
            "id": w["id"], "name": T(w["name"]), "super": bool(w.get("super", False)),
            "angle": w["angle"], "damage": w["damage"], "radius": w["radius"], "price": w["price"],
            "attrs": w["attrs"], "color": w["color"],
            "icon": art(f"res://assets/weapons/{w['id']}/tier0.png", f"weapons/{w['id']}_0.png"),
            "tiers": [art(f"res://assets/weapons/{w['id']}/tier{t}.png", f"weapons/{w['id']}_{t}.png") for t in range(4)],
            "projectile": {"img": art(proj_src, f"projectiles/{w['id']}.png", crop=True), "trail": proj.get("trail"),
                           "size": proj.get("size"), "wind_scale": proj.get("wind_scale", 1.0),
                           "spin": proj.get("spin", 0), "align": bool(proj.get("align", False))},
            "pow": {"name": T(w["pow"]["name"]), "desc": T(w["pow"]["desc"]), **pow_rules,
                    "art": art(f"res://assets/effects/pow/{w['id']}/frame_03.png", f"pow/{w['id']}.png")
                    or art(f"res://assets/effects/pow/{w['id']}/icon.png", f"pow/{w['id']}.png")},
            "drops": drops.get(w["id"], []),
        })

    cosmetics = []
    for c in items["cosmetics"]:
        slot = c["slot"]
        if slot == "roupa":
            icon = art(f"res://assets/characters/{c['skin']}/south.png", f"cosmetics/{c['id']}.png", crop=True)
        elif slot == "cabelo":
            icon = art("res://assets/cosmetics/cabelo/icon.png", f"cosmetics/{c['id']}.png", tint=c["dye"])
        else:
            icon = art(f"res://assets/cosmetics/{c['art']}/icon.png", f"cosmetics/{c['id']}.png", crop=True) \
                or art(f"res://assets/cosmetics/{c['art']}/front.png", f"cosmetics/{c['id']}.png", crop=True)
        cosmetics.append({"id": c["id"], "slot": slot, "slot_name": T(SLOT_NAMES[slot]), "gender": c["gender"],
                          "name": T(c["name"]), "price": c["price"], "premium": bool(c.get("premium", False)),
                          "attrs": c.get("attrs", {}), "dye": c.get("dye"), "icon": icon})

    enemies = []
    appears = {}
    for inst in instances:
        for p, phase in enumerate(inst["phases"]):
            for wave in phase["waves"]:
                for eid in wave:
                    entry = appears.setdefault(eid, [])
                    if [inst["id"], p] not in entry:
                        entry.append([inst["id"], p])
    for e in combat["enemies"]:
        abilities = []
        for a in e.get("abilities", []):
            rules = {k: v for k, v in a.items() if k not in ("name", "fx", "color", "id")}
            abilities.append({"id": a["id"], "name": T(a["name"]), **rules})
        enemies.append({
            "id": e["id"], "name": T(e["name"]), "rank": e["rank"], "hp": e["hp"], "damage": e["damage"],
            "fury_damage": e.get("fury_damage"), "radius": e.get("radius"), "agility": e.get("agility"),
            "angle": e.get("angle"), "hit_radius": e.get("hit_radius"), "faces": e.get("faces", "left"),
            "attack": T(e.get("attack") or None), "fury_name": T(e.get("fury_name")),
            "mechanics": e.get("mechanics", []), "summon": e.get("summon"), "color": e.get("color"),
            "sprite": art(e["sprite"], f"enemies/{e['id']}.png", crop=True),
            "abilities": abilities, "appears": appears.get(e["id"], []),
        })

    arenas = []
    used = {}
    for inst in instances:
        for p, phase in enumerate(inst["phases"]):
            used.setdefault(phase["map"], []).append([inst["id"], p])
    for m in combat["maps"]:
        arenas.append({"id": m["id"], "name": T(m["name"]), "size": m["size"], "pve_only": bool(m.get("pve_only", False)),
                       "ambience": m.get("ambience"),
                       "thumb": art(f"res://assets/maps/thumbs/{m['id']}.png", f"maps/{m['id']}_thumb.png"),
                       "bg": webp(m["bg"], f"img/game/maps/{m['id']}.webp"), "used": used.get(m["id"], [])})

    inst_out = []
    for inst in instances:
        inst_out.append({
            "id": inst["id"], "name": T(inst["name"]), "boss": inst["boss"], "minion": inst["minion"],
            "color": inst["color"], "desc": T(inst["desc"]),
            "preview": art(inst["preview"], f"instances/{inst['id']}_preview.png"),
            "map_icon": art(f"res://assets/items/maps/{inst['id']}.png", f"instances/{inst['id']}_map.png"),
            "phases": [{"name": T(ph["name"]), "map": ph["map"], "objective": ph.get("objective"),
                        "turns": ph.get("turns"), "waves": ph["waves"]} for ph in inst["phases"]],
            "loot": inst["loot"],
        })

    mi = combat["map_items"]
    map_items = {k: mi[k] for k in ("max_level", "hp_per_level", "damage_per_level", "reward_per_level", "free_reward",
                                    "drop_chance", "drop_level", "other_instance", "qualities", "threat_quantity", "loot")}
    map_items["mods"] = [{"id": m["id"], "kind": m["kind"], "text": T(m["text"]), "range": m.get("range")} for m in mi["mods"]]

    affixes = items["affixes"]
    affix_out = {"slots": affixes["slots"], "counts": affixes["counts"], "tiers": affixes["tiers"], "limits": affixes["limits"]}
    for group in ("weapon", "armor"):
        affix_out[group] = [{"id": a["id"], "text": T(a["text"]), "values": a["values"]} for a in affixes[group]]

    strengthen = dict(items["strengthen"])
    strengthen["stones"] = [{"id": s["id"], "name": T(s["name"]), "level": s["level"], "min_instance_level": s["min_instance_level"],
                             "icon": art(s["icon"], f"items/{s['id']}.png")} for s in items["strengthen"]["stones"]]

    rewards = combat["rewards"]
    reward_cards = [{"id": c["id"], "name": T(c["name"]), "weight": c["weight"], "rarity": c["rarity"],
                     "icon": art(c["icon"], f"rewards/{c['id']}.png")} for c in rewards["cards"] + rewards["pvp_cards"]]

    data = {
        "meta": {"version": game_version(), "built": datetime.date.today().isoformat()},
        "combat": {k: combat[k] for k in ("base_hp", "hp_per_level", "base_agility", "agility_per_level", "energy",
                                           "move_energy_per_px", "move_speed", "turn_seconds", "turn_seconds_options",
                                           "gravity", "min_speed", "max_speed", "wind_max", "wind_accel", "charge_rate", "pow_max", "pow_per_damage_dealt",
                                           "pow_per_damage_taken", "pow_per_turn", "splash_scale", "delay", "fly")},
        "pve": combat["pve"], "party_scaling": combat["party_scaling"],
        "ranks": [T(r) for r in RANKS], "max_level": 60,
        "attr_names": {k: T(v) for k, v in ATTR_NAMES.items()},
        "qualities": [{"id": q["id"], "label": T(q["label"]), "damage": q["damage"], "attrs": q["attrs"],
                       "price": q["price"], "color": q["color"]} for q in items["qualities"]],
        "strengthen": strengthen,
        "auras": [{"from": a["from"], "to": a["to"], "name": T(a["name"]), "color": a["color"]} for a in items["auras"]],
        "affixes": affix_out,
        "currencies": [{"id": c["id"], "name": T(c["name"]), "rarity": c["rarity"], "weight": c["weight"],
                        "min_level": c["min_level"], "per_level": c["per_level"], "desc": T(c["desc"]),
                        "icon": art(c["icon"], f"currency/{c['id']}.png")} for c in items["currencies"]],
        "auction": items["auction"],
        "weapons": weapons,
        "auxiliary": [{"id": a["id"], "name": T(a["name"]), "price": a["price"], "uses": a["uses"],
                       "heal_ratio": a.get("heal_ratio"), "shield": a.get("shield"), "desc": T(a["desc"]),
                       "icon": art(a["icon"], f"aux/{a['id']}.png", crop=True)} for a in items["auxiliary"]],
        "cosmetics": cosmetics,
        "skills": [{"id": s["id"], "key": s["key"], "name": T(s["name"]), "energy": s["energy"], "delay": s["delay"],
                    "desc": T(s["desc"]), "icon": art(s["icon"], f"skills/{s['id']}.png")} for s in combat["items"]],
        "tools": [{"id": t["id"], "name": T(t["name"]), "price": t["price"], "desc": T(t["desc"]),
                   "icon": art(t["icon"], f"tools/{t['id']}.png", crop=True)} for t in combat["tools"]],
        # 0.16: status effects from the monsters and the elite affixes.
        "statuses": [{"id": st["id"], "name": T(st["name"]), "label": T(st["label"]), "desc": T(st["desc"]),
                      "color": st["color"], "turns": st["turns"],
                      "icon": art(st["icon"], f"status/{st['id']}.png")} for st in combat.get("statuses", [])],
        "elites": {**{k: v for k, v in combat.get("elites", {}).items() if k != "affixes"},
                   "affixes": [{"id": a["id"], "name": T(a["name"]), "desc": T(a["desc"]), "color": a["color"],
                                "status": a.get("status", []),
                                "icon": art(a["icon"], f"status/elite_{a['id']}.png")}
                               for a in combat.get("elites", {}).get("affixes", [])]},
        "enemies": enemies,
        "instances": inst_out,
        "map_items": map_items,
        "arenas": arenas,
        "rewards": {k: rewards[k] for k in ("win_exp", "loss_exp", "exp_per_damage", "exp_per_kill",
                                             "merit_win", "merit_loss", "merit_per_kill")},
        "reward_cards": reward_cards,
        "achievements": [{"id": a["id"], "name": T(a["name"]), "desc": T(a["desc"]), "stat": a["stat"],
                          "at_least": a["at_least"],
                          "icon": art(f"store/steam/achievements/{a['id']}.png", f"achievements/{a['id']}.png")}
                         for a in achievements["achievements"]],
        "store": [{"sku": p["sku"], "name": T(p["name"]), "desc": T(p["desc"]), "items": p["items"],
                   "prices": {k: p["prices"][k] for k in ("BRL", "USD", "EUR")}} for p in store["products"]],
        "icons": {
            "coin": art("res://assets/items/moeda.png", "items/moeda.png"),
            "plane": art("res://assets/ui/icons/plane.png", "ui/plane.png"),
            "pow": art("res://assets/ui/icons/pow.png", "ui/pow.png"),
            "trophy": art("res://assets/ui/icons/trophy.png", "ui/trophy.png"),
            "crown": art("res://assets/ui/icons/crown.png", "ui/crown.png"),
            "star": art("res://assets/ui/icons/star.png", "ui/star.png"),
            "team": art("res://assets/ui/icons/team.png", "ui/team.png"),
            "shop": art("res://assets/ui/icons/shop.png", "ui/shop.png"),
            "bag": art("res://assets/ui/icons/bag.png", "ui/bag.png"),
            "mail": art("res://assets/ui/icons/mail.png", "ui/mail.png"),
            "help": art("res://assets/ui/icons/help.png", "ui/help.png"),
            "power": art("res://assets/ui/icons/power.png", "ui/power.png"),
            "search": art("res://assets/ui/icons/search.png", "ui/search.png"),
            "play": art("res://assets/ui/icons/play.png", "ui/play.png"),
            "shield": art("res://assets/ui/icone_escudo.png", "ui/shield.png"),
            "heal": art("res://assets/ui/icone_cura.png", "ui/heal.png"),
        },
    }
    return data


def copy_extras():
    """Characters, effects and backgrounds for the landing page, screenshots and fonts."""
    extras = {
        "hero": {
            "nilo": art("res://assets/characters/nilo/south.png", "characters/nilo.png", crop=True),
            "lani": art("res://assets/characters/lani/south.png", "characters/lani.png", crop=True),
            "nilo_prone": art("res://assets/characters/nilo/prone/east.png", "characters/nilo_prone.png", crop=True),
            "lani_prone": art("res://assets/characters/lani/prone/east.png", "characters/lani_prone.png", crop=True),
            "samurai": art("res://assets/characters/roupa_samurai/south.png", "characters/samurai.png", crop=True),
            "princesa": art("res://assets/characters/roupa_princesa/south.png", "characters/princesa.png", crop=True),
            "ninja": art("res://assets/characters/roupa_ninja/south.png", "characters/ninja.png", crop=True),
            "maga": art("res://assets/characters/roupa_maga/south.png", "characters/maga.png", crop=True),
            "title_bg": webp("res://assets/title/title_bg.png", "img/game/title_bg.webp"),
            "city": webp("docs/screens/city.png", "img/shots/city.webp"),
            "pow_cutin": webp("docs/screens/pow_cutin.png", "img/shots/pow_cutin.webp"),
        },
        "terrain": {k: art(f"res://assets/maps/terrain/celeste_{k}.png", f"terrain/celeste_{k}.png") for k in "abc"},
        "explosion": [art(f"res://assets/effects/explosion/frame_{i:02d}.png", f"effects/explosion_{i}.png") for i in range(7)],
    }
    shots = {}
    for lang in ("pt", "en"):
        folder = os.path.join(ROOT, "store", "steam", "screenshots", lang)
        shots[lang] = []
        for name in sorted(os.listdir(folder)):
            if name.endswith(".png"):
                shots[lang].append(webp(os.path.join("store", "steam", "screenshots", lang, name),
                                        f"img/shots/{lang}/{name[:-4]}.webp"))
    extras["shots"] = shots
    fonts = os.path.join(SITE, "fonts")
    os.makedirs(fonts, exist_ok=True)
    for name in ("PixelOperator-Bold.ttf", "PixelOperator-LICENSE.txt", "Jersey10-Regular.ttf", "OFL.txt"):
        shutil.copyfile(os.path.join(ROOT, "assets", "fonts", name),
                        os.path.join(fonts, "Jersey10-OFL.txt" if name == "OFL.txt" else name))
    return extras


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--no-logo", action="store_true", help="skip tools/make_logo.py")
    args = parser.parse_args()
    PO.update(load_po(os.path.join(ROOT, "locale", "en.po")))
    if os.path.isdir(IMG):
        shutil.rmtree(IMG)
    data = build_data()
    data["extras"] = copy_extras()
    os.makedirs(os.path.join(SITE, "data"), exist_ok=True)
    text = json.dumps(data, ensure_ascii=False, separators=(",", ":"))
    with open(os.path.join(SITE, "data", "gamedata.js"), "w", encoding="utf-8") as handle:
        handle.write("/* Generated by tools/build_site.py from shared/balance and locale/en.po. Do not edit. */\n")
        handle.write("window.GF_DATA = " + text + ";\n")
    missing = [w["id"] for w in data["weapons"] if not w["icon"]] + [e["id"] for e in data["enemies"] if not e["sprite"]]
    if missing:
        print("missing art:", missing)
    untranslated = sorted({v["pt"] for v in walk_texts(data) if v["pt"] == v["en"] and re.search(r"[a-zà-ú]{4}", v["pt"])})
    print(f"gamedata.js: {len(text) // 1024} KB, {len(COPIED)} images, "
          f"{len(data['weapons'])} weapons, {len(data['enemies'])} monsters, {len(data['instances'])} instances")
    if untranslated:
        print("same in both languages (check en.po):", ", ".join(untranslated[:30]))
    if not args.no_logo:
        import make_logo
        sys.argv = ["make_logo.py", "--out", os.path.join(SITE, "img", "brand")]
        make_logo.main()
    social_cards()


def social_cards():
    """1200x630 link previews (og:image): the logo over the Ilha Celeste sky."""
    brand = os.path.join(SITE, "img", "brand")
    sky = Image.open(os.path.join(ROOT, "assets", "maps", "bg", "ilha_celeste.png")).convert("RGBA")
    sky = sky.resize((sky.width * 2, sky.height * 2), Image.NEAREST)
    left = (sky.width - 1200) // 2
    sky = sky.crop((left, 70, left + 1200, 700))
    shade = Image.new("RGBA", sky.size, (8, 10, 31, 70))
    sky.alpha_composite(shade)
    for lang in ("pt", "en"):
        card = sky.copy()
        logo = Image.open(os.path.join(brand, f"gustfire_logo_{lang}.png")).convert("RGBA")
        logo = logo.resize((logo.width * 2, logo.height * 2), Image.NEAREST)
        width = 1040
        logo = logo.resize((width, round(logo.height * width / logo.width)), Image.LANCZOS)
        card.alpha_composite(logo, ((1200 - logo.width) // 2, (630 - logo.height) // 2 - 10))
        card.convert("RGB").save(os.path.join(brand, f"og_{lang}.png"), optimize=True)


def walk_texts(node):
    if isinstance(node, dict):
        if set(node.keys()) == {"pt", "en"}:
            yield node
            return
        for value in node.values():
            yield from walk_texts(value)
    elif isinstance(node, list):
        for value in node:
            yield from walk_texts(value)


if __name__ == "__main__":
    main()
