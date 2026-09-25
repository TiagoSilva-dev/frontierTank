#!/usr/bin/env python3
"""Measure paper-doll anchors for every character skin.

For assets/characters/<skin>/ it writes anchors.json with, in pixel coordinates of
each image:
  south: head box, eye line and upper-back point of the standing front view (menus);
  prone: the same for the prone east view used in battle;
  clips: per-frame head position for prone/{idle,crawl,shoot} (tracked by template
         matching against the static prone sprite), so hats and glasses follow the head;
  hair:  hex colours of the hair, used by the hair-dye shader.

Usage: python tools/character_anchors.py [skin ...]   (needs Pillow + numpy)
"""
import colorsys
import json
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), "..", "assets", "characters")


def load(path):
    return np.array(Image.open(path).convert("RGBA")).astype(np.int32)


def bbox(img):
    ys, xs = np.nonzero(img[:, :, 3] > 40)
    return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1


def south_anchors(img):
    x0, y0, x1, y1 = bbox(img)
    height = y1 - y0
    head_h = round(height * 0.47)
    rows = img[y0 : y0 + round(head_h * 0.55), :, 3] > 40
    cols = np.nonzero(rows.any(axis=0))[0]
    # Hair can flare out; the face width is measured on the eye row instead.
    eye_y = y0 + round(head_h * 0.66)
    eye_cols = np.nonzero(img[eye_y, :, 3] > 40)[0]
    cx = (cols.min() + cols.max() + 1) / 2
    width = max(cols.max() + 1 - cols.min(), eye_cols.max() + 1 - eye_cols.min()) if len(eye_cols) else cols.max() + 1 - cols.min()
    return {
        "head": [round(cx, 1), int(y0), int(width), int(head_h)],
        "eyes": [round(cx, 1), int(eye_y)],
        "back": [round(cx, 1), int(y0 + head_h + round(height * 0.12))],
        "bottom": int(y1),
    }


def column_tops(img, x0, x1):
    alpha = img[:, :, 3] > 40
    tops = {}
    for x in range(x0, x1):
        ys = np.nonzero(alpha[:, x])[0]
        if len(ys):
            tops[x] = ys.min()
    return tops


def prone_anchors(img):
    x0, y0, x1, y1 = bbox(img)
    tops = column_tops(img, x0, x1)
    width = x1 - x0
    body_line = np.median([tops[x] for x in tops if x < x0 + width * 0.45])
    right = [x for x in tops if x > x0 + width * 0.4]
    top = min(tops[x] for x in right)
    # The cranium: columns rising well above the back (scarves and collars stay lower).
    limit = top + 0.5 * (body_line - top)
    head_cols = [x for x in right if tops[x] <= limit]
    hx0, hx1 = min(head_cols), max(head_cols) + 1
    head_w = round((hx1 - hx0) * 1.08)
    head_h = round(head_w * 0.95)
    cx = (hx0 + hx1) / 2
    back_x = hx0 - round(head_w * 0.12)
    back_y = tops.get(back_x, body_line)
    return {
        "head": [round(cx, 1), int(top), int(head_w), int(head_h)],
        "eyes": [round(hx1 - head_w * 0.2, 1), int(top + round(head_h * 0.62))],
        "back": [int(back_x), int(back_y)],
        "bottom": int(y1),
    }


def track(static, head, frame, guess):
    """Find the head patch of `static` inside `frame`, near `guess` (dx, dy)."""
    cx, top, w, h = head
    px0, py0 = int(cx - w / 2) - 2, max(0, top - 2)
    patch = static[py0 : py0 + h + 4, px0 : px0 + w + 4]
    mask = patch[:, :, 3:4] > 40
    best, best_off = None, guess
    ph, pw = patch.shape[:2]
    for dy in range(guess[1] - 12, guess[1] + 13):
        for dx in range(guess[0] - 12, guess[0] + 13):
            fx, fy = px0 + dx, py0 + dy
            if fx < 0 or fy < 0 or fx + pw > frame.shape[1] or fy + ph > frame.shape[0]:
                continue
            region = frame[fy : fy + ph, fx : fx + pw]
            diff = np.abs(region - patch) * mask
            score = diff.sum()
            if best is None or score < best:
                best, best_off = score, (dx, dy)
    return best_off


def count_colors(region):
    colors = {}
    for px in region.reshape(-1, 4):
        if px[3] < 200:
            continue
        key = tuple(int(v) for v in px[:3])
        colors[key] = colors.get(key, 0) + 1
    return colors


def hair_palette(img, head, fraction=0.42):
    cx, top, w, h = head
    region = img[top : top + round(h * fraction), int(cx - w / 2) : int(cx + w / 2)]
    colors = count_colors(region)
    if not colors:
        return []
    # Skin must never be dyed: drop the colours that cover most of the cheeks.
    face = count_colors(img[top + round(h * 0.62) : top + round(h * 0.9), int(cx - w * 0.2) : int(cx + w * 0.2)])
    total = sum(face.values())
    covered = 0
    for color, count in sorted(face.items(), key=lambda item: -item[1]):
        if covered > total * 0.7:
            break
        covered += count
        colors.pop(color, None)
    if not colors:
        return []
    # Keep colours close to the dominant hair hue; drops goggles, clips and outline.
    dominant = max(colors, key=colors.get)
    hue = colorsys.rgb_to_hsv(*[v / 255 for v in dominant])[0]
    result = []
    for color, count in colors.items():
        h2, s2, v2 = colorsys.rgb_to_hsv(*[v / 255 for v in color])
        dist = min(abs(h2 - hue), 1 - abs(h2 - hue))
        if count >= 2 and dist < 0.09 and s2 > 0.12 and v2 > 0.1:
            result.append("%02x%02x%02x" % color)
    return sorted(result)


def analyse(skin):
    folder = os.path.join(ROOT, skin)
    result = {}
    south = load(os.path.join(folder, "south.png"))
    result["south"] = south_anchors(south)
    result["hair"] = hair_palette(south, result["south"]["head"])
    prone_path = os.path.join(folder, "prone", "east.png")
    if os.path.exists(prone_path):
        prone = load(prone_path)
        result["prone"] = prone_anchors(prone)
        clips = {}
        for clip in ("idle", "crawl", "shoot"):
            clip_dir = os.path.join(folder, "prone", clip)
            if not os.path.isdir(clip_dir):
                continue
            frames = sorted(f for f in os.listdir(clip_dir) if f.startswith("frame_") and f.endswith(".png"))
            points = []
            guess = None
            for name in frames:
                frame = load(os.path.join(clip_dir, name))
                if guess is None:
                    # Frame 0 is the static sprite on a larger canvas: centre offset first.
                    guess = ((frame.shape[1] - prone.shape[1]) // 2, (frame.shape[0] - prone.shape[0]) // 2)
                    guess = track(prone, result["prone"]["head"], frame, guess)
                dx, dy = track(prone, result["prone"]["head"], frame, guess)
                guess = (dx, dy)
                points.append([dx, dy])
            clips[clip] = {"size": [int(frame.shape[1]), int(frame.shape[0])], "offsets": points}
        result["clips"] = clips
    with open(os.path.join(folder, "anchors.json"), "w") as handle:
        json.dump(result, handle, indent=1)
    return result


if __name__ == "__main__":
    skins = sys.argv[1:] or sorted(d for d in os.listdir(ROOT) if os.path.isdir(os.path.join(ROOT, d)))
    for skin in skins:
        if os.path.exists(os.path.join(ROOT, skin, "south.png")):
            data = analyse(skin)
            print(skin, data["south"]["head"], data.get("prone", {}).get("head"), len(data["hair"]), "hair colours")
