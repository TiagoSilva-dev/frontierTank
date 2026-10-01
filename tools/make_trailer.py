#!/usr/bin/env python3
"""Vertical (9:16) promo video of the game, for TikTok / Reels / Shorts.

Two steps, both from this one script (no Python packages needed, only ffmpeg and Godot):

  1. record  Godot plays scripted scenes of the real game (tools/trailer/director.gd) and its
             movie writer saves each one as an .avi with the game's own sound effects.
  2. compose ffmpeg cuts the scenes, frames them on a 1080x1920 canvas (blurred copy of the
             footage behind), adds captions, the logo, one music track and renders the mp4.

  GODOT=/path/to/godot python3 tools/make_trailer.py            # record + compose, English
  GODOT=... python3 tools/make_trailer.py --lang pt_BR          # Portuguese captions and game
  python3 tools/make_trailer.py --skip-record                   # only compose (raw .avi kept)

The raw scenes go to build/trailer/<lang>/ (git-ignored); the video to store/trailer/.
The scenes use a scratch profile (user://trailer_<scene>.json): the player's save is never touched.
"""
import argparse
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FONT = ROOT / "assets/fonts/Jersey10-Regular.ttf"
LOGO = ROOT / "assets/title/logo_en.png"
BG = ROOT / "assets/title/title_bg.png"
MUSIC = ROOT / "assets/audio/music/battle.ogg"
GOLD = "0xffd25a"
W, H = 1080, 1920

# ---------- scenes recorded from the game ----------
# name -> (frames at 30 fps, game arguments). --seg=duel / boss are the director's scripts.
DUEL = "--seg=duel --screen=battle --team=2 --auto=1"
BOSS = "--seg=boss --screen=pve_battle --demo=1 --level=14 --zoom=1.2 --items=plus1,dmg50 --pow_turn=2"
POW = "--seg=duel --screen=city --demo=1 --target=battle --team=2 --map=ilha_celeste --zoom=1.4 --pow_turn=1 --items=plus1"
SCENES = {
    "fpow": (330, f"{DUEL} --demo=founder --map=ilha_celeste --zoom=1.3 --pow_turn=1 --items=plus1"),
    "duel": (480, f"{DUEL} --demo=founder --map=patio_templo --zoom=1.5 --items=plus1,dmg50 --pow_turn=99"),
    "boss": (540, f"{BOSS} --instance=templo_sol --level=10 --phase=3"),
    "viking": (480, f"{BOSS} --instance=fiorde_viking --phase=3"),
    "masks": (480, f"{BOSS} --instance=trono_mascaras --phase=2"),
    "ruins": (480, f"{BOSS} --instance=ilha_ruinas --phase=3"),
    "pow1": (240, f"{POW} --weapon=canhao_arco_iris"),
    "pow2": (240, f"{POW} --weapon=trovao"),
    "pow3": (240, f"{POW} --weapon=cabeca_de_boi"),
    "shop": (180, "--seg=none --screen=founder --demo=founder"),
    "bag": (120, "--seg=none --screen=bag --demo=founder"),
}

# ---------- the edit ----------
# kind "fit": the whole 16:9 frame at full width (menus, cut-ins); "crop": the middle of the
# battle, bigger (the camera follows the action, so it stays in the middle).
# (scene, start s, length s, kind, title key, subtitle key, logo on top)
EDIT = [
    ("fpow", 2.3, 2.1, "fit", "shot", "", True),
    ("fpow", 4.4, 1.1, "crop", "shot", "", True),
    ("fpow", 8.9, 1.8, "crop", "sun", "", True),
    ("@logo", 0, 2.2, "", "", "", False),
    ("duel", 0.4, 5.6, "crop", "aim", "aim_sub", True),
    ("boss", 1.0, 2.2, "crop", "inst", "inst_sub", True),
    ("viking", 3.0, 2.2, "crop", "inst", "inst_sub", True),
    ("masks", 3.5, 2.2, "crop", "inst", "inst_sub", True),
    ("ruins", 9.0, 2.2, "crop", "inst", "inst_sub", True),
    ("pow1", 2.7, 2.6, "crop", "pow", "pow_sub", True),
    ("pow2", 2.7, 2.6, "crop", "pow", "pow_sub", True),
    ("pow3", 2.8, 2.4, "crop", "pow", "pow_sub", True),
    ("shop", 0.2, 3.2, "fit", "founder", "founder_sub", True),
    ("bag", 0.2, 2.6, "fit", "founder", "set_sub", True),
    ("@end", 0, 3.6, "", "", "", False),
]

TEXT = {
    "en": {
        "shot": "ONE SHOT.", "sun": "ONE SUN.",
        "logo_sub": "TURN-BASED ARTILLERY",
        "aim": "AIM. FIRE. DESTROY.", "aim_sub": "PvP with skills 1-9 and wind to read",
        "inst": "5 INSTANCES", "inst_sub": "3 phases - elites - epic bosses",
        "pow": "EVERY WEAPON", "pow_sub": "has its own POW special",
        "founder": "FOUNDER PACK", "founder_sub": "Paladino do Sol edition",
        "set_sub": "Skin - wings - aura - pet - POW",
        "end1": "FOUNDER PACK", "end2": "LIMITED EDITION", "end3": "COMING SOON TO STEAM",
    },
    "pt_BR": {
        "shot": "UM TIRO.", "sun": "UM SOL.",
        "logo_sub": "ARTILHARIA POR TURNOS",
        "aim": "MIRE. ATIRE. DESTRUA.", "aim_sub": "PvP com habilidades 1-9 e vento para ler",
        "inst": "5 INSTÂNCIAS", "inst_sub": "3 fases - elites - chefes épicos",
        "pow": "CADA ARMA", "pow_sub": "tem seu próprio especial POW",
        "founder": "PACOTE FUNDADOR", "founder_sub": "Edição Paladino do Sol",
        "set_sub": "Skin - asas - aura - pet - POW",
        "end1": "PACOTE FUNDADOR", "end2": "EDIÇÃO LIMITADA", "end3": "EM BREVE NA STEAM",
    },
}


def run(cmd, **kw):
    r = subprocess.run([str(c) for c in cmd], capture_output=True, text=True, **kw)
    if r.returncode != 0:
        sys.exit(f"command failed: {' '.join(str(c) for c in cmd)}\n{r.stderr[-2000:]}")
    return r


def record(godot, raw, lang):
    raw.mkdir(parents=True, exist_ok=True)

    def one(item):
        name, (frames, game_args) = item
        out = raw / f"{name}.avi"
        cmd = [godot, "--path", ROOT, "--rendering-driver", "opengl3", "--write-movie", out, "--fixed-fps", "30",
               "--script", "tools/trailer/director.gd", "--", f"--len={frames}", "--frames=1000000", "--out=x",
               f"--lang={lang}", f"--profile=user://trailer_{name}.json"] + game_args.split()
        # A script error leaves Godot hanging: the timeout is the safety net.
        subprocess.run([str(c) for c in cmd], capture_output=True, timeout=900)
        print("recorded", name, flush=True)

    with ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(one, SCENES.items()))


def drawtext(file, text_file, size, color, y, fade_in=0.25, fade_out=0.2, length=3.0, border=7, still=False):
    """A caption centred on the canvas, sliding up while it fades in (`still`: already on
    screen from the clip before, so it just stays)."""
    if still:
        return (f"drawtext=fontfile='{file}':textfile='{text_file}':fontsize={size}:fontcolor={color}:"
                f"borderw={border}:bordercolor=black:x=(w-text_w)/2:y={y}")
    return (f"drawtext=fontfile='{file}':textfile='{text_file}':fontsize={size}:fontcolor={color}:"
            f"borderw={border}:bordercolor=black:x=(w-text_w)/2:"
            f"y={y}+24*(1-min(1\\,t/{fade_in})):"
            f"alpha='min(1\\,t/{fade_in})'")


def fit_size(text, size, max_width=960):
    """Jersey 10 is about 0.34 em wide per character: long titles shrink to stay on the canvas."""
    return min(size, int(max_width / (0.34 * max(1, len(text)))))


def caption_file(tmp, name, text):
    path = tmp / f"{name}.txt"
    path.write_text(text, encoding="utf-8")
    return path


def make_clip(raw, tmp, index, spec, strings):
    scene, start, length, kind, title_key, sub_key, with_logo = spec
    previous = EDIT[index - 1] if index > 0 else None
    still = previous is not None and previous[4] == title_key and previous[6] == with_logo
    out = tmp / f"clip_{index:02d}.mp4"
    if scene.startswith("@"):
        return make_card(tmp, index, scene, length, strings)
    if kind == "fit":
        crop, block_w, block_h = "crop=1280:720:0:0", W, 608
    else:
        crop, block_w, block_h = "crop=840:720:220:0", W, 926
    block_y = 940 - block_h // 2
    title = caption_file(tmp, f"t{index}", strings[title_key]) if title_key else None
    sub = caption_file(tmp, f"s{index}", strings[sub_key]) if sub_key else None
    chain = [
        "[0:v]fps=30,split=2[a][b]",
        f"[a]scale={W}:{H}:force_original_aspect_ratio=increase,crop={W}:{H},gblur=sigma=36,eq=brightness=-0.18:saturation=0.9[bg]",
        f"[b]{crop},scale=iw*3:ih*3:flags=neighbor,scale={block_w}:{block_h}:flags=lanczos[fg]",
        f"[bg][fg]overlay=0:{block_y}[v0]",
        f"[v0]drawbox=x=0:y={block_y - 5}:w={W}:h=5:color={GOLD}@0.9:t=fill,drawbox=x=0:y={block_y + block_h}:w={W}:h=5:color={GOLD}@0.9:t=fill[v1]",
    ]
    last = "v1"
    if with_logo:
        chain.append(f"[1:v]scale=420:-1:flags=neighbor[lg]")
        chain.append(f"[{last}][lg]overlay=(W-w)/2:70[v2]")
        last = "v2"
    texts = []
    if title:
        texts.append(drawtext(FONT, title, fit_size(strings[title_key], 170), "white", 240, length=length, still=still))
    if sub:
        texts.append(drawtext(FONT, sub, fit_size(strings[sub_key], 80, 1000), GOLD, block_y + block_h + 60, length=length, border=6, still=still))
    if texts:
        chain.append(f"[{last}]" + ",".join(texts) + "[vout]")
        last = "vout"
    af = f"[0:a]afade=t=in:d=0.03,afade=t=out:st={length - 0.06:.2f}:d=0.06[aout]"
    cmd = ["ffmpeg", "-y", "-v", "error", "-ss", f"{start}", "-t", f"{length}", "-i", raw / f"{scene}.avi",
           "-loop", "1", "-t", f"{length}", "-i", LOGO,
           "-filter_complex", ";".join(chain + [af]), "-map", f"[{last}]", "-map", "[aout]",
           "-r", "30", "-c:v", "libx264", "-preset", "medium", "-crf", "17", "-pix_fmt", "yuv420p",
           "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-ac", "2", out]
    run(cmd)
    return out


def make_card(tmp, index, kind, length, strings):
    """The two cards with no gameplay: the logo sting and the end card, on the title's own art."""
    out = tmp / f"clip_{index:02d}.mp4"
    big = kind == "@end"
    lines = []
    if big:
        lines = [(strings["end1"], 124, GOLD, 1080), (strings["end2"], 84, "white", 1210), (strings["end3"], 74, "0xa8e0ff", 1420)]
    else:
        lines = [(strings["logo_sub"], 76, "white", 1130)]
    chain = [
        f"[0:v]scale=iw*6:ih*6:flags=neighbor,crop={W}:{H}:x='(iw-{W})/2+sin(t*0.6)*90':y='(ih-{H})/2',eq=brightness=-0.12,fps=30[bg]",
        f"[1:v]scale={900 if big else 940}:-1:flags=neighbor[lg]",
        f"[bg][lg]overlay=(W-w)/2:{560 if big else 640}:format=auto[v0]",
    ]
    last = "v0"
    for i, (text, size, color, y) in enumerate(lines):
        path = caption_file(tmp, f"c{index}_{i}", text)
        chain.append(f"[{last}]" + drawtext(FONT, path, size, color, y, length=length, border=8) + f"[c{i}]")
        last = f"c{i}"
    cmd = ["ffmpeg", "-y", "-v", "error", "-loop", "1", "-t", f"{length}", "-i", BG, "-loop", "1", "-t", f"{length}", "-i", LOGO,
           "-f", "lavfi", "-t", f"{length}", "-i", "anullsrc=r=48000:cl=stereo",
           "-filter_complex", ";".join(chain), "-map", f"[{last}]", "-map", "2:a",
           "-r", "30", "-c:v", "libx264", "-preset", "medium", "-crf", "17", "-pix_fmt", "yuv420p",
           "-c:a", "aac", "-b:a", "192k", out]
    run(cmd)
    return out


def compose(raw, lang, out_path):
    strings = TEXT[lang]
    tmp = ROOT / "build/trailer" / lang / "clips"
    tmp.mkdir(parents=True, exist_ok=True)
    clips = [make_clip(raw, tmp, i, spec, strings) for i, spec in enumerate(EDIT)]
    (tmp / "list.txt").write_text("".join(f"file '{c.name}'\n" for c in clips))
    joined = tmp / "joined.mp4"
    run(["ffmpeg", "-y", "-v", "error", "-f", "concat", "-safe", "0", "-i", tmp / "list.txt", "-c", "copy", joined])
    total = sum(spec[2] for spec in EDIT)
    # One music track under the game's own sound effects, normalised to a social-media level.
    mix = (f"[1:a]volume=0.55,afade=t=in:d=0.6,afade=t=out:st={total - 1.8:.2f}:d=1.8[m];"
           f"[0:a][m]amix=inputs=2:duration=first:normalize=0,loudnorm=I=-14:TP=-1.5:LRA=11[a]")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    run(["ffmpeg", "-y", "-v", "error", "-i", joined, "-i", MUSIC, "-filter_complex", mix, "-map", "0:v", "-map", "[a]",
         "-c:v", "copy", "-c:a", "aac", "-b:a", "192k", "-t", f"{total:.2f}", "-movflags", "+faststart", out_path])
    print(f"{out_path} ({total:.1f} s)")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--lang", default="en", choices=list(TEXT))
    parser.add_argument("--skip-record", action="store_true")
    parser.add_argument("--godot", default=os.environ.get("GODOT", "godot"))
    options = parser.parse_args()
    raw = ROOT / "build/trailer" / options.lang
    if not options.skip_record:
        record(options.godot, raw, options.lang)
    suffix = "en" if options.lang == "en" else "pt"
    compose(raw, options.lang, ROOT / f"store/trailer/gustfire_trailer_{suffix}_9x16.mp4")


if __name__ == "__main__":
    main()
