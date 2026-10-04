#!/usr/bin/env python3
"""Vertical (9:16) promo video of the MOBILE version, for TikTok / Reels / Shorts.

The footage is the real game in touch mode, played with fingers: the director
(tools/trailer/director.gd, --seg=pilot) sends the same ScreenTouch events a phone sends to the
on-screen controls (walk, aim, FOGO, the skill drawer, POW) and draws a marker under each finger.
This script records the scenes and then composes them: a phone frame that turns sideways, the
game inside it, big captions, a tap sound for every touch and one music track.

  GODOT=/path/to/godot python3 tools/make_mobile_trailer.py            # record + compose, English
  GODOT=... python3 tools/make_mobile_trailer.py --lang pt_BR          # Portuguese
  python3 tools/make_mobile_trailer.py --skip-record                   # only compose
  python3 tools/make_mobile_trailer.py --record-only [--scene duel]    # only record

Needs ffmpeg, Godot and Pillow (the phone frame is drawn with it). Raw scenes go to
build/trailer/mobile/<lang>/ (git-ignored); the videos to store/trailer/.
The scenes use scratch profiles (user://trailer_<scene>.json): the player's save is never touched.
"""
import argparse
import json
import math
import os
import random
import struct
import subprocess
import sys
import wave
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from make_trailer import BG, FONT, GOLD, H, LOGO, MUSIC, ROOT, W, caption_file, drawtext, fit_size, run

PIXEL = ROOT / "assets/fonts/PixelOperator-Bold.ttf"
ICON = ROOT / "website/img/brand/gustfire_icon_512.png"
FPS = 30

# ---------- scenes recorded from the game ----------
# name -> (frames at 30 fps, game arguments)
PILOT = "--seg=pilot --touch=1 --seed=7 --charge=1.3 --walk=0.4 --lead=0.6"
BOSS = f"{PILOT} --screen=pve_battle --demo=1 --zoom=1.2 --items= --pow_turn=1"
POW = f"{PILOT} --screen=city --demo=founder --target=battle --team=2 --zoom=1.4 --pow_turn=1"
SCENES = {
    "duel": (660, f"{PILOT} --screen=battle --team=2 --demo=founder --map=ilha_celeste --zoom=1.3 --items=plus1,dmg50"),
    "pow1": (330, f"{POW} --map=patio_templo --weapon=trovao"),
    "pow2": (330, f"{POW} --map=ilha_celeste --weapon=canhao_arco_iris"),
    "boss": (480, f"{BOSS} --instance=templo_sol --level=10 --phase=3"),
    "city": (420, "--seg=city --touch=1 --seed=7 --screen=city --demo=founder"),
    "hunt": (300, "--seg=none --touch=1 --seed=7 --screen=pet --tab=Caçada --demo=1 --hunt=960"),
}


def record(godot, raw, lang, only=None):
    raw.mkdir(parents=True, exist_ok=True)

    def one(item):
        name, (frames, game_args) = item
        out = raw / f"{name}.avi"
        cmd = [godot, "--path", ROOT, "--rendering-driver", "opengl3", "--write-movie", out, "--fixed-fps", str(FPS),
               "--script", "tools/trailer/director.gd", "--", f"--len={frames}", "--frames=1000000", "--out=x",
               f"--lang={lang}", f"--profile=user://trailer_{name}.json", f"--taplog={raw / (name + '_taps.json')}"] + game_args.split()
        # A script error leaves Godot hanging: the timeout is the safety net.
        subprocess.run([str(c) for c in cmd], capture_output=True, timeout=900)
        print("recorded", name, flush=True)

    scenes = {k: v for k, v in SCENES.items() if only is None or k in only}
    with ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(one, scenes.items()))



# ---------- the phone frame (drawn here, so the repo carries no extra art) ----------
BODY = (922, 534)         # the phone, lying on its side
BORDER = 18               # bezel around the screen
SCREEN = (BODY[0] - 2 * BORDER, BODY[1] - 2 * BORDER)
PAD = 8                   # room for the side buttons
CENTRE_Y = 717            # the phone's centre on the canvas
PHONE_AT = ((W - BODY[0]) // 2, CENTRE_Y - BODY[1] // 2)
SCREEN_AT = (PHONE_AT[0] + BORDER, PHONE_AT[1] + BORDER)
PANEL = (960, 540)        # the zoom under the phone
PANEL_AT = ((W - PANEL[0]) // 2, 1110)
URLBAR = (900, 116)


def make_assets(out):
    """phone_frame.png (the body over the footage, a hole for the screen, a soft shadow),
    phone_idle.png (the same phone with its screen off, for the turn) and urlbar.png."""
    from PIL import Image, ImageDraw, ImageFilter

    out.mkdir(parents=True, exist_ok=True)
    k = 3  # drawn at 3x and shrunk: smooth corners
    radius, inner = 56, 26

    def body_image(screen_fill):
        w, h = (BODY[0] + 2 * PAD) * k, (BODY[1] + 2 * PAD) * k
        img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        # side buttons, behind the body
        d.rounded_rectangle([(PAD + 620) * k, 0, (PAD + 700) * k, (PAD + 14) * k], 4 * k, fill=(46, 51, 64, 255))
        d.rounded_rectangle([(PAD + 160) * k, 0, (PAD + 222) * k, (PAD + 14) * k], 4 * k, fill=(46, 51, 64, 255))
        box = [PAD * k, PAD * k, (PAD + BODY[0]) * k, (PAD + BODY[1]) * k]
        d.rounded_rectangle(box, radius * k, fill=(61, 68, 86, 255))
        d.rounded_rectangle([box[0] + 3 * k, box[1] + 3 * k, box[2] - 3 * k, box[3] - 3 * k], (radius - 3) * k, fill=(13, 15, 21, 255))
        # speaker slit and camera on the bezel (the phone lies on its left side)
        cy = (PAD + BODY[1] // 2) * k
        d.rounded_rectangle([(PAD + 6) * k, cy - 20 * k, (PAD + 11) * k, cy + 20 * k], 3 * k, fill=(44, 49, 62, 255))
        d.ellipse([(PAD + 5) * k, cy - 48 * k, (PAD + 12) * k, cy - 41 * k], fill=(22, 36, 70, 255))
        sx, sy = (PAD + BORDER) * k, (PAD + BORDER) * k
        screen = [sx, sy, sx + SCREEN[0] * k, sy + SCREEN[1] * k]
        d.rounded_rectangle(screen, inner * k, fill=screen_fill)
        return img, screen

    # the frame over the footage: the screen is a hole
    body, screen = body_image((0, 0, 0, 255))
    hole = Image.new("L", body.size, 255)
    ImageDraw.Draw(hole).rounded_rectangle(screen, inner * k, fill=0)
    body.putalpha(Image.composite(body.getchannel("A"), Image.new("L", body.size, 0), hole))
    body = body.resize((body.width // k, body.height // k), Image.LANCZOS)
    canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    silhouette = Image.new("L", (W, H), 0)
    ImageDraw.Draw(silhouette).rounded_rectangle(
        [PHONE_AT[0], PHONE_AT[1] + 24, PHONE_AT[0] + BODY[0], PHONE_AT[1] + BODY[1] + 24], radius, fill=170)
    shadow.putalpha(silhouette.filter(ImageFilter.GaussianBlur(30)))
    canvas.alpha_composite(shadow)
    canvas.alpha_composite(body, (PHONE_AT[0] - PAD, PHONE_AT[1] - PAD))
    # nothing of the shadow over the screen
    mask = Image.new("L", (W, H), 255)
    ImageDraw.Draw(mask).rounded_rectangle(
        [SCREEN_AT[0], SCREEN_AT[1], SCREEN_AT[0] + SCREEN[0], SCREEN_AT[1] + SCREEN[1]], inner, fill=0)
    canvas.putalpha(Image.composite(canvas.getchannel("A"), Image.new("L", (W, H), 0), mask))
    canvas.save(out / "phone_frame.png")

    # the same phone, screen off: dark blue with the icon (it turns with the phone)
    idle, screen = body_image((10, 16, 44, 255))
    icon = Image.open(ICON).convert("RGBA")
    side = 170 * k
    icon = icon.resize((side, side), Image.LANCZOS)
    glow = Image.new("RGBA", idle.size, (0, 0, 0, 0))
    cx, cy = idle.width // 2, idle.height // 2
    ImageDraw.Draw(glow).ellipse([cx - 210 * k, cy - 210 * k, cx + 210 * k, cy + 210 * k], fill=(255, 150, 50, 70))
    glow = glow.filter(ImageFilter.GaussianBlur(55 * k))
    idle.alpha_composite(glow)
    idle.alpha_composite(icon, ((idle.width - side) // 2, (idle.height - side) // 2))
    idle = idle.resize((idle.width // k, idle.height // k), Image.LANCZOS)
    idle.save(out / "phone_idle.png")

    # the browser's address bar of the end card
    bar = Image.new("RGBA", (URLBAR[0] * k, URLBAR[1] * k), (0, 0, 0, 0))
    d = ImageDraw.Draw(bar)
    d.rounded_rectangle([0, 0, bar.width - 1, bar.height - 1], bar.height // 2, fill=(244, 246, 251, 255))
    # a padlock
    cx, cy = 66 * k, URLBAR[1] // 2 * k
    d.rounded_rectangle([cx - 15 * k, cy - 2 * k, cx + 15 * k, cy + 22 * k], 4 * k, fill=(44, 160, 90, 255))
    d.arc([cx - 11 * k, cy - 22 * k, cx + 11 * k, cy + 6 * k], 180, 360, fill=(44, 160, 90, 255), width=5 * k)
    bar = bar.resize(URLBAR, Image.LANCZOS)
    bar.save(out / "urlbar.png")


# ---------- the tap sound ----------
RATE = 48000


def tick(down):
    """A soft tap: a short falling blip and a tiny click (the finger landing or leaving)."""
    length = int(RATE * (0.06 if down else 0.04))
    f0, f1, gain = (1700.0, 900.0, 0.42) if down else (900.0, 600.0, 0.2)
    rng = random.Random(7)
    samples, phase = [], 0.0
    for i in range(length):
        x = i / length
        phase += 2 * math.pi * (f0 + (f1 - f0) * x) / RATE
        value = math.sin(phase) * math.exp(-x * 6.0)
        if i < 120:
            value += (rng.random() * 2 - 1) * 0.5 * (1 - i / 120)
        samples.append(value * gain)
    return samples


def tap_track(taps_json, seconds, out):
    """taps_<scene>.json (the director's log: [frame, 1 = down / 0 = up]) -> a mono wav."""
    total = int(RATE * (seconds + 1))
    track = [0.0] * total
    for frame, down in json.loads(Path(taps_json).read_text()) if Path(taps_json).exists() else []:
        start = int(frame / FPS * RATE)
        for i, v in enumerate(tick(bool(down))):
            if start + i < total:
                track[start + i] += v
    with wave.open(str(out), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, v)) * 32000)) for v in track))


def hook_sound(out, seconds):
    """The phone turning (a breath of filtered noise that rises and falls) and the screen
    waking up (two soft bell notes)."""
    total = int(RATE * seconds)
    track = [0.0] * total
    rng = random.Random(3)
    low = 0.0
    start, end = int(0.45 * RATE), int(1.4 * RATE)
    for i in range(start, end):
        x = (i - start) / (end - start)
        envelope = math.sin(math.pi * x) ** 2
        cutoff = 0.02 + 0.22 * math.sin(math.pi * x)
        low += cutoff * ((rng.random() * 2 - 1) - low)
        track[i] += low * envelope * 1.6
    ding = int(1.42 * RATE)
    for i in range(int(0.9 * RATE)):
        x = i / RATE
        value = (math.sin(2 * math.pi * 1318.5 * x) + 0.5 * math.sin(2 * math.pi * 1976.0 * x)) * math.exp(-x * 5.5)
        if ding + i < total:
            track[ding + i] += value * 0.22
    with wave.open(str(out), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, v)) * 32000)) for v in track))


# ---------- the edit ----------
# "@hook" and "@end" are cards. Otherwise: the recorded scene, from `start` for `length` seconds
# of the VIDEO (the footage runs `speed` times as fast: 0.5 is slow motion).
#   kind "split": the phone with the whole game on its screen, and under it a zoom (`box` =
#                 w, h, x, y of the game's 1280x720 frame, 16:9) on what matters;
#   kind "big":   no phone, the box (default: the whole frame) as big as the canvas allows.
FRAME = (1280, 720, 0, 0)
ACTION = (800, 450, 240, 70)      # the middle of the battle, without the controls
HIT = (720, 405, 400, 138)        # where the first shot lands: both fighters, no controls
DRAWER = (576, 324, 392, 300)     # the skill drawer and the button that opens it
THUMB = (576, 324, 704, 396)      # the arrows, FOGO and the POW orb
BAR = (704, 396, 480, 324)        # the force bar's end, FOGO and the arrows
FIELD = (576, 384, 338, 152)      # the Caçada field, 3:2
EDIT = [
    dict(scene="@hook", length=2.3, title="hook", sub="hook_sub"),
    dict(scene="duel", start=0.4, length=2.2, kind="split", box=DRAWER, title="skills", sub="skills_sub"),
    dict(scene="duel", start=3.0, length=1.2, kind="split", box=THUMB, title="aim", sub="aim_sub"),
    dict(scene="duel", start=4.2, length=1.4, kind="split", box=BAR, title="hold", sub="hold_sub"),
    dict(scene="duel", start=5.6, length=1.5, kind="split", box=ACTION, speed=1.8, title="release", sub="release_sub"),
    dict(scene="duel", start=8.35, length=1.6, kind="big", box=HIT, speed=0.5, title="hit", sub="hit_sub"),
    dict(scene="pow1", start=0.5, length=1.5, kind="split", box=THUMB, title="pow", sub="pow_sub"),
    dict(scene="pow1", start=3.95, length=1.55, kind="big", box=FRAME, title="pow", sub="pow_sub2"),
    dict(scene="pow2", start=3.45, length=1.5, kind="big", box=FRAME, title="pow", sub="pow_sub2"),
    dict(scene="boss", start=4.05, length=1.4, kind="big", box=FRAME, title="boss", sub="boss_sub"),
    dict(scene="boss", start=6.0, length=2.0, kind="split", box=ACTION, speed=1.5, title="boss", sub="boss_sub"),
    dict(scene="city", start=0.3, length=3.0, kind="big", box=FRAME, title="town", sub="town_sub"),
    dict(scene="hunt", start=1.0, length=3.0, kind="big", box=FIELD, title="hunt", sub="hunt_sub"),
    dict(scene="@end", length=4.6),
]

TEXT = {
    "en": {
        "hook": "TURN YOUR PHONE.", "hook_sub": "Artillery now fits in your pocket",
        "skills": "9 SKILLS", "skills_sub": "one tap in the drawer",
        "aim": "AIM WITH A THUMB", "aim_sub": "the arrows set the angle",
        "hold": "HOLD TO CHARGE", "hold_sub": "feel the force build up",
        "release": "RELEASE TO FIRE", "release_sub": "wind, gravity, one shot",
        "hit": "DIRECT HIT!", "hit_sub": "the terrain breaks with it",
        "pow": "TAP POW", "pow_sub": "every weapon has its own special", "pow_sub2": "anime cut-in included",
        "boss": "BOSS EXPEDITIONS", "boss_sub": "3 phases - up to 4 players",
        "town": "ALL BY TOUCH", "town_sub": "town, pets, bag, shop",
        "hunt": "PETS HUNT ALONE", "hunt_sub": "even with the game closed",
        "end1": "PLAY NOW", "end2": "IN YOUR PHONE'S BROWSER", "end3": "ANDROID AND IPHONE",
        "end4": "Google Play and App Store: coming soon",
    },
    "pt_BR": {
        "hook": "VIRE O CELULAR.", "hook_sub": "Artilharia agora cabe no bolso",
        "skills": "9 HABILIDADES", "skills_sub": "um toque na gaveta",
        "aim": "MIRE COM O POLEGAR", "aim_sub": "as setas ajustam o ângulo",
        "hold": "SEGURE E CARREGUE", "hold_sub": "sinta a força crescer",
        "release": "SOLTE PARA ATIRAR", "release_sub": "vento, gravidade, um tiro",
        "hit": "ACERTOU!", "hit_sub": "o terreno desmancha junto",
        "pow": "TOQUE NO POW", "pow_sub": "cada arma tem o seu especial", "pow_sub2": "com corte de anime e tudo",
        "boss": "EXPEDIÇÕES", "boss_sub": "chefes em 3 fases - até 4 jogadores",
        "town": "TUDO POR TOQUE", "town_sub": "cidade, mascotes, mochila, loja",
        "hunt": "ELES CAÇAM SOZINHOS", "hunt_sub": "seus mascotes, com o jogo fechado",
        "end1": "JOGUE AGORA", "end2": "NO NAVEGADOR DO CELULAR", "end3": "ANDROID E IPHONE",
        "end4": "Google Play e App Store: em breve",
    },
}
URL = "gustfire.online/jogar"


def tempo(speed):
    """atempo only takes 0.5 to 2 per stage."""
    stages = []
    while speed < 0.5:
        stages.append("atempo=0.5")
        speed /= 0.5
    stages.append(f"atempo={speed:.4f}")
    return ",".join(stages)


def text_size(text, size, max_width=980):
    """Jersey 10 capitals are about 0.43 em wide: long captions shrink to stay on the canvas."""
    longest = max(text.split("\n"), key=len)
    return min(size, int(max_width / (0.43 * max(1, len(longest)))))


def backdrop(dim):
    """The title art, enlarged and blurred, drifting a little: the same sunset behind every shot."""
    return (f"scale=iw*6:ih*6:flags=neighbor,crop={W}:{H}:x='(iw-{W})/2+sin(t*0.6)*90':y='(ih-{H})/2',"
            f"gblur=sigma=14,eq=brightness={dim},fps=30")


def make_clip(raw, tmp, assets, index, spec, strings):
    scene, length = spec["scene"], spec["length"]
    if scene == "@hook":
        return make_hook(tmp, assets, index, spec, strings)
    if scene == "@end":
        return make_end(tmp, assets, index, spec, strings)
    out = tmp / f"clip_{index:02d}.mp4"
    start, speed, kind = spec.get("start", 0), spec.get("speed", 1.0), spec.get("kind", "split")
    box = spec.get("box", ACTION)
    title_key, sub_key = spec["title"], spec["sub"]
    previous = EDIT[index - 1] if index > 0 else {}
    still = previous.get("title") == title_key
    read = length * speed
    scale_up = "scale=iw*3:ih*3:flags=neighbor"
    crop = f"crop={box[0]}:{box[1]}:{box[2]}:{box[3]}"
    chain = [f"[0:v]setpts=(PTS-STARTPTS)/{speed},fps=30,{'split=2[a][b]' if kind == 'split' else 'null[b]'}", f"[4:v]{backdrop(-0.28)}[bg]"]
    if kind == "split":
        chain += [
            f"[a]{scale_up},scale={SCREEN[0]}:{SCREEN[1]}:flags=lanczos[fg]",
            f"[b]{crop},{scale_up},scale={PANEL[0]}:{PANEL[1]}:flags=lanczos[pan]",
            f"[bg][fg]overlay={SCREEN_AT[0]}:{SCREEN_AT[1]}[v0]",
            "[v0][3:v]overlay=0:0[v1]",
            f"[v1][pan]overlay={PANEL_AT[0]}:{PANEL_AT[1]}[v2]",
            f"[v2]drawbox=x={PANEL_AT[0] - 5}:y={PANEL_AT[1] - 5}:w={PANEL[0] + 10}:h={PANEL[1] + 10}:color={GOLD}@0.95:t=5[v3]",
        ]
        title_y, sub_y = 265, PHONE_AT[1] + BODY[1] + 24
    else:
        block_h = int(W * box[1] / box[0])
        block_y = 940 - block_h // 2
        chain += [
            f"[b]{crop},{scale_up},scale={W}:{block_h}:flags=lanczos[pan]",
            f"[bg][pan]overlay=0:{block_y}[v2]",
            f"[v2]drawbox=x=0:y={block_y - 5}:w={W}:h=5:color={GOLD}@0.9:t=fill,"
            f"drawbox=x=0:y={block_y + block_h}:w={W}:h=5:color={GOLD}@0.9:t=fill[v3]",
        ]
        title_y, sub_y = 265, block_y + block_h + 50
    chain += ["[1:v]scale=420:-1:flags=neighbor[lg]", "[v3][lg]overlay=(W-w)/2:100[v4]"]
    title = caption_file(tmp, f"t{index}", strings[title_key])
    sub = caption_file(tmp, f"s{index}", strings[sub_key])
    texts = [drawtext(FONT, title, text_size(strings[title_key], 140), "white", title_y, length=length, still=still),
             drawtext(FONT, sub, text_size(strings[sub_key], 72, 1000), GOLD, sub_y, length=length, border=6, still=still)]
    chain.append("[v4]" + ",".join(texts) + "[vout]")
    tempo_filter = tempo(speed) if speed != 1 else "anull"
    af = (f"[0:a]{tempo_filter},afade=t=in:d=0.03,afade=t=out:st={length - 0.06:.2f}:d=0.06[ga];"
          f"[2:a]{tempo_filter}[ta];[ga][ta]amix=inputs=2:duration=first:normalize=0[aout]")
    cmd = ["ffmpeg", "-y", "-v", "error",
           "-ss", f"{start}", "-t", f"{read}", "-i", raw / f"{scene}.avi",
           "-loop", "1", "-t", f"{length}", "-i", LOGO,
           "-ss", f"{start}", "-t", f"{read}", "-i", tmp / f"taps_{scene}.wav",
           "-loop", "1", "-t", f"{length}", "-i", assets / "phone_frame.png",
           "-loop", "1", "-t", f"{length}", "-i", BG,
           "-filter_complex", ";".join(chain + [af]), "-map", "[vout]", "-map", "[aout]",
           "-r", "30", "-c:v", "libx264", "-preset", "medium", "-crf", "17", "-pix_fmt", "yuv420p",
           "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-ac", "2", out]
    run(cmd)
    return out


def make_hook(tmp, assets, index, spec, strings):
    """The phone stands up, then turns on its side and wakes: 'turn your phone'."""
    length = spec["length"]
    out = tmp / f"clip_{index:02d}.mp4"
    x = "min(max((t-0.45)/0.95\\,0)\\,1)"
    ease = f"(1+2.70158*pow({x}-1\\,3)+1.70158*pow({x}-1\\,2))"
    title = caption_file(tmp, f"t{index}", strings[spec["title"]])
    sub = caption_file(tmp, f"s{index}", strings[spec["sub"]])
    chain = [
        f"[0:v]{backdrop(-0.34)}[bg]",
        f"[1:v]format=rgba,rotate=a='PI/2*(1-{ease})':c=black@0:ow=1200:oh=1200[ph]",
        f"[bg][ph]overlay=(W-w)/2:{CENTRE_Y}-h/2[v0]",
        "[v0]" + drawtext(FONT, title, text_size(strings[spec["title"]], 150), "white", 90, length=length, border=8) + ","
        + drawtext(FONT, sub, text_size(strings[spec["sub"]], 76, 1000), GOLD, CENTRE_Y + 480, length=length, border=6) + "[vout]",
    ]
    hook_sound(tmp / "hook.wav", length)
    run(["ffmpeg", "-y", "-v", "error", "-loop", "1", "-t", f"{length}", "-i", BG, "-loop", "1", "-t", f"{length}", "-i", assets / "phone_idle.png",
         "-i", tmp / "hook.wav",
         "-filter_complex", ";".join(chain), "-map", "[vout]", "-map", "2:a",
         "-r", "30", "-c:v", "libx264", "-preset", "medium", "-crf", "17", "-pix_fmt", "yuv420p",
         "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-ac", "2", out])
    return out


def make_end(tmp, assets, index, spec, strings):
    """The call to action: the address types itself into a browser bar."""
    length = spec["length"]
    out = tmp / f"clip_{index:02d}.mp4"
    bar_x, bar_y = (W - URLBAR[0]) // 2, 1150
    text_x, step, t0 = bar_x + 120, 0.075, 0.9
    shown = [(URL[:i] + "|", t0 + (i - 1) * step, t0 + i * step) for i in range(1, len(URL) + 1)]
    t = t0 + len(URL) * step
    while t < length:
        shown += [(URL + "|", t, t + 0.35), (URL, t + 0.35, t + 0.7)]
        t += 0.7
    chain = [
        f"[0:v]{backdrop(-0.3)}[bg]",
        "[1:v]scale=820:-1:flags=neighbor[lg]",
        "[bg][lg]overlay=(W-w)/2:250:format=auto[v0]",
        "[2:v]format=rgba[bar]",
        f"[v0][bar]overlay={bar_x}:'if(lt(t,0.5),{bar_y}+80*(1-t/0.5),{bar_y})':format=auto[v1]",
    ]
    last = "v1"
    font = ROOT / "assets/fonts/AtkinsonHyperlegible-Bold.ttf"
    for i, (text, a, b) in enumerate(shown):
        path = tmp / f"url{i}.txt"
        path.write_text(text, encoding="utf-8")
        chain.append(f"[{last}]drawtext=fontfile='{font}':textfile='{path}':fontsize=52:fontcolor=0x20243a:"
                     f"x={text_x}:y={bar_y + 28}:enable='between(t,{a:.3f},{b:.3f})'[u{i}]")
        last = f"u{i}"
    lines = [
        (strings["end1"], 150, GOLD, 760),
        (strings["end2"], 70, "white", 960),
        (strings["end3"], 64, "0xa8e0ff", 1330),
        (strings["end4"], 52, "white", 1430),
    ]
    for i, (text, size, color, y) in enumerate(lines):
        path = caption_file(tmp, f"e{index}_{i}", text)
        chain.append(f"[{last}]" + drawtext(FONT, path, text_size(text, size), color, y, length=length, border=8) + f"[c{i}]")
        last = f"c{i}"
    run(["ffmpeg", "-y", "-v", "error", "-loop", "1", "-t", f"{length}", "-i", BG, "-loop", "1", "-t", f"{length}", "-i", LOGO,
         "-loop", "1", "-t", f"{length}", "-i", assets / "urlbar.png",
         "-f", "lavfi", "-t", f"{length}", "-i", "anullsrc=r=48000:cl=stereo",
         "-filter_complex", ";".join(chain), "-map", f"[{last}]", "-map", "3:a",
         "-r", "30", "-c:v", "libx264", "-preset", "medium", "-crf", "17", "-pix_fmt", "yuv420p",
         "-c:a", "aac", "-b:a", "192k", out])
    return out


def compose(raw, lang, out_path):
    global LOGO
    # The logo carries its tagline: "Artilharia nos céus" for the Portuguese video.
    LOGO = ROOT / ("assets/title/logo_en.png" if lang == "en" else "assets/title/logo.png")
    strings = TEXT[lang]
    tmp = ROOT / "build/trailer/mobile" / lang / "clips"
    tmp.mkdir(parents=True, exist_ok=True)
    assets = ROOT / "build/trailer/mobile/assets"
    make_assets(assets)
    for scene, (frames, _) in SCENES.items():
        if (raw / f"{scene}.avi").exists():
            tap_track(raw / f"{scene}_taps.json", frames / FPS, tmp / f"taps_{scene}.wav")
    clips = [make_clip(raw, tmp, assets, i, spec, strings) for i, spec in enumerate(EDIT)]
    (tmp / "list.txt").write_text("".join(f"file '{c.name}'\n" for c in clips))
    joined = tmp / "joined.mp4"
    run(["ffmpeg", "-y", "-v", "error", "-f", "concat", "-safe", "0", "-i", tmp / "list.txt", "-c", "copy", joined])
    total = sum(spec["length"] for spec in EDIT)
    mix = (f"[1:a]volume=0.5,afade=t=in:d=0.6,afade=t=out:st={total - 1.8:.2f}:d=1.8[m];"
           f"[0:a][m]amix=inputs=2:duration=first:normalize=0,loudnorm=I=-14:TP=-1.5:LRA=11[a]")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    run(["ffmpeg", "-y", "-v", "error", "-i", joined, "-i", MUSIC, "-filter_complex", mix, "-map", "0:v", "-map", "[a]",
         "-c:v", "copy", "-c:a", "aac", "-b:a", "192k", "-t", f"{total:.2f}", "-movflags", "+faststart", out_path])
    print(f"{out_path} ({total:.1f} s)")
    return out_path


# The site plays a lighter copy (720x1280) with a poster; both go to website/video/.
POSTER_AT = 7.0


def web_copy(video, lang):
    suffix = "en" if lang == "en" else "pt"
    folder = ROOT / "website/video"
    folder.mkdir(parents=True, exist_ok=True)
    small = folder / f"gustfire_mobile_{suffix}.mp4"
    run(["ffmpeg", "-y", "-v", "error", "-i", video, "-vf", "scale=720:1280:flags=lanczos", "-c:v", "libx264", "-preset", "slow",
         "-crf", "27", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "96k", "-movflags", "+faststart", small])
    poster = folder / f"mobile_{suffix}.jpg"
    run(["ffmpeg", "-y", "-v", "error", "-ss", f"{POSTER_AT}", "-i", video, "-frames:v", "1", "-vf", "scale=540:960:flags=lanczos", "-q:v", "4", poster])
    print(f"{small} ({small.stat().st_size / 1e6:.1f} MB), {poster} ({poster.stat().st_size // 1000} KB)")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--lang", default="en", choices=["en", "pt_BR"])
    parser.add_argument("--skip-record", action="store_true")
    parser.add_argument("--record-only", action="store_true")
    parser.add_argument("--no-web", action="store_true", help="do not write the site's copy to website/video/")
    parser.add_argument("--scene", action="append", help="only these scenes (with --record-only)")
    parser.add_argument("--godot", default=os.environ.get("GODOT", "godot"))
    options = parser.parse_args()
    raw = ROOT / "build/trailer/mobile" / options.lang
    if not options.skip_record:
        record(options.godot, raw, options.lang, options.scene)
    if options.record_only:
        return
    suffix = "en" if options.lang == "en" else "pt"
    video = compose(raw, options.lang, ROOT / f"store/trailer/gustfire_mobile_{suffix}_9x16.mp4")
    if not options.no_web:
        web_copy(video, options.lang)


if __name__ == "__main__":
    main()
