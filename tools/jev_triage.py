#!/usr/bin/env python3
"""Jev (TypeSafe System One) as the first step of every request: a cheap typed triage.

One call, several independent questions over the same request text (they run in parallel
on the server). The output tells the working session where the request lives, how big it
is and which shortcuts apply, before any file is read:

    python3 tools/jev_triage.py "texto do pedido do usuário"

The key comes only from the environment (TYPESAFE_API_KEY) and is sent only to
api.typesafe.ai. Output is one JSON object on stdout; probabilities below THRESHOLD are
reported as "unsure" so the caller falls back to normal exploration instead of trusting them.
"""
import json
import os
import sys
import urllib.error
import urllib.request

URL = "https://api.typesafe.ai/v1/systemone"
MODEL = "jev-latest"
THRESHOLD = 0.6
MIN_PROMPT = 12  # shorter messages ("ok", "valeu") and slash commands skip the call
MAX_PROMPT = 4000

CONTEXT = (
    "Frontier Tank (Gustfire): a DDTank-style artillery game in Godot 4 (GDScript) with pixel art, "
    "a Go API + Godot headless online server, a website/wiki, balance data and docs/ROADMAP.md."
)

QUESTIONS = {
    "area": {
        "type": "choice",
        "instructions": "Which part of the project does this request mostly change or ask about?",
        "criteria": {
            "combat_gameplay": "Shots, physics, terrain, weapons, skills, status effects, enemies, match flow",
            "ui_hud_menus": "HUD, lobby, shop, inventory, menus, fonts, layout",
            "pixel_art_assets": "Sprites, skins, weapons, effects, icons, animations",
            "audio": "Music, sound effects, voices",
            "online_server": "Go API, headless server, lockstep, accounts, matchmaking, deploy",
            "website_wiki": "The website, wiki, store page, build_site",
            "balance_data": "Numbers, drops, prices, progression, simulations",
            "tooling_docs_git": "Scripts, docs, roadmap, git, settings, plugins",
            "question_only": "Only asks something about the project or the assistant's behaviour",
        },
    },
    "kind": {
        "type": "choice",
        "instructions": "What kind of work is requested?",
        "criteria": {
            "explain_or_answer": "Wants information, no change",
            "bugfix": "Something is broken or behaves wrongly",
            "new_feature": "Add behaviour that does not exist",
            "refactor": "Restructure without changing behaviour",
            "content_or_data": "Add or change items, levels, texts, numbers",
            "art_or_audio_asset": "Create or revise art or sound",
            "review_or_check": "Verify, test or audit existing work",
            "setup_or_config": "Install, configure or change how the assistant works",
        },
    },
    "size": {
        "type": "score",
        "instructions": "How much work does this request need?",
        "criteria": [
            "Answer or one-line change, no exploration",
            "Small edit in one or two files",
            "Several files, one system",
            "Cross-cutting change with design decisions and tests",
        ],
    },
    "design_choice": {
        "type": "noul",
        "instructions": "Does the request involve choosing between visual or gameplay design options (look, feel, readability, balance) where a scored comparison would help?",
    },
    "needs_assets": {
        "type": "noul",
        "instructions": "Does the request need new generated art or audio (PixelLab, synthesized sound)?",
    },
    "ambiguous": {
        "type": "noul",
        "instructions": "Is the request ambiguous enough that a decision belonging to the user must be asked before acting?",
    },
}


def triage(text: str) -> dict:
    key = os.environ.get("TYPESAFE_API_KEY")
    if not key:
        sys.exit("TYPESAFE_API_KEY is not set")
    body = json.dumps({"state": {"project": CONTEXT, "request": text}, "model": MODEL, "questions": QUESTIONS}).encode()
    request = urllib.request.Request(URL, body, {"Authorization": "Bearer " + key, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            answers = json.load(response)["answers"]
    except urllib.error.HTTPError as error:
        sys.exit("Jev error %d: %s" % (error.code, error.read().decode()[:300]))
    out = {}
    for qid, answer in answers.items():
        if answer["type"] == "choice":
            sure = answer["probabilities"].get(answer["choice"], 0.0) >= THRESHOLD
            out[qid] = answer["choice"] if sure else "unsure"
        elif answer["type"] == "score":
            out[qid] = round(answer["score"], 1)
        else:
            out[qid] = round(answer["noul"], 2)
    return out


def hook() -> None:
    """UserPromptSubmit hook: stdin is the hook JSON; stdout adds the triage to the model's context.

    Never blocks the prompt: any failure (no key, network, API) leaves the output empty and exits 0.
    """
    try:
        prompt = json.load(sys.stdin).get("prompt", "").strip()
        if len(prompt) < MIN_PROMPT or prompt.startswith("/"):
            return
        result = triage(prompt[:MAX_PROMPT])
    except (SystemExit, Exception):
        return
    context = "Jev triage (tools/jev_triage.py, advisory; see memory jev-first-every-request): " + json.dumps(result, ensure_ascii=False)
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": context}}))


if __name__ == "__main__":
    if sys.argv[1:] == ["--hook"]:
        hook()
    elif len(sys.argv) < 2:
        sys.exit("usage: jev_triage.py \"request text\" | --hook")
    else:
        print(json.dumps(triage(" ".join(sys.argv[1:])), ensure_ascii=False))
