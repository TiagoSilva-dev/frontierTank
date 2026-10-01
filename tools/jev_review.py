#!/usr/bin/env python3
"""Jev (TypeSafe System One) as a design gate for the Founder Pack.

Jev answers typed questions (score / choice / noul) about a text `state`; it never writes
prose. Here it judges *descriptions* of design options (silhouettes, POW timelines, VFX
radius policies, production priority) against the rules of the brief, so every decision in
docs/FOUNDER_PACK.md has numbers behind it and can be re-run when an option changes.

    TYPESAFE_API_KEY=... python3 tools/jev_review.py docs/founder/jev_plan.json

The key comes only from the environment and is sent only to api.typesafe.ai.
Output: a ranking per group on stdout and, as raw answers, the optional second argument
(default docs/founder/jev_results.json).

Plan format: {"context": str, "groups": [{"id", "title", "questions": {qid: question},
"weights": {qid: w}, "options": [{"id", "text"}]}]}. A weight is applied to the answer
normalised to 0..1 (score / top level); a negative weight rewards a LOW answer (risks).
"""
import concurrent.futures
import json
import os
import sys
import time
import urllib.error
import urllib.request

URL = "https://api.typesafe.ai/v1/systemone"
MODEL = "jev-latest"


def ask(state, questions, retries: int = 4):
    key = os.environ.get("TYPESAFE_API_KEY")
    if not key:
        sys.exit("TYPESAFE_API_KEY is not set")
    body = json.dumps({"state": state, "model": MODEL, "questions": questions}).encode()
    for attempt in range(retries):
        request = urllib.request.Request(URL, body, {"Authorization": "Bearer " + key, "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            if error.code in (429, 529) and attempt < retries - 1:
                time.sleep(2 ** attempt)
                continue
            sys.exit("Jev error %d: %s" % (error.code, error.read().decode()[:400]))
    return {}


def normalised(question, answer) -> float:
    """0..1: score / top level, or the yes-probability of a noul."""
    if answer["type"] == "score":
        return answer["score"] / (len(question["criteria"]) - 1)
    if answer["type"] == "noul":
        return answer["noul"]
    raise ValueError("only score and noul answers can be weighted")


def run(plan_path: str, out_path: str = "docs/founder/jev_results.json") -> None:
    with open(plan_path, encoding="utf-8") as handle:
        plan = json.load(handle)
    jobs = []
    for group in plan["groups"]:
        for option in group["options"]:
            state = {"context": plan.get("context", ""), "option": option["text"]}
            jobs.append((group["id"], option["id"], state, group["questions"]))
    results = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        futures = {pool.submit(ask, state, questions): (gid, oid) for gid, oid, state, questions in jobs}
        for future in concurrent.futures.as_completed(futures):
            gid, oid = futures[future]
            results.setdefault(gid, {})[oid] = future.result()["answers"]
    out = {}
    for group in plan["groups"]:
        gid = group["id"]
        rows = []
        for option in group["options"]:
            answers = results[gid][option["id"]]
            total = 0.0
            shown = {}
            for qid, question in group["questions"].items():
                if question["type"] == "choice":
                    shown[qid] = answers[qid]["choice"]
                    continue
                level = normalised(question, answers[qid])
                shown[qid] = round(level, 2)
                weight = group.get("weights", {}).get(qid, 0.0)
                total += abs(weight) * ((1.0 - level) if weight < 0 else level)
            rows.append((total, option["id"], shown))
        rows.sort(key=lambda row: -row[0])
        print("\n== %s: %s" % (gid, group["title"]))
        for total, oid, shown in rows:
            print("  %-24s total=%.3f  %s" % (oid, total, "  ".join("%s=%s" % item for item in shown.items())))
        out[gid] = {"title": group["title"], "ranking": [row[1] for row in rows], "totals": {row[1]: round(row[0], 4) for row in rows}, "normalised": {row[1]: row[2] for row in rows}, "raw": results[gid]}
    os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as handle:
        json.dump(out, handle, ensure_ascii=False, indent=1)


if __name__ == "__main__":
    run(*sys.argv[1:3])
