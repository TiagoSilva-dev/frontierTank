#!/usr/bin/env python3
"""Write server/api/admin_catalog.json: what the admin panel may send as a gift.

The Go API cannot read the game's data, and a letter with an id the game does not know is
marked as received without giving anything. So the list of assets (the currencies and the
strengthen stones, exactly what CurrencyExchange.valid_asset accepts) is generated here from
shared/balance/items.json and embedded in the API.

  python tools/admin_catalog.py           rewrite the file
  python tools/admin_catalog.py --check   exit 1 if it is stale (run it after changing items.json)
"""
import json
import os
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
SOURCE = os.path.join(ROOT, "shared", "balance", "items.json")
TARGET = os.path.join(ROOT, "server", "api", "admin_catalog.json")


def build() -> str:
    with open(SOURCE, encoding="utf-8") as handle:
        items = json.load(handle)
    assets = [{"id": c["id"], "name": c["name"], "kind": "currency"} for c in items["currencies"]]
    assets += [{"id": s["id"], "name": s["name"], "kind": "stone"} for s in items["strengthen"]["stones"]]
    return json.dumps({"assets": assets}, ensure_ascii=False, indent=1) + "\n"


def main() -> int:
    text = build()
    if "--check" in sys.argv:
        current = open(TARGET, encoding="utf-8").read() if os.path.exists(TARGET) else ""
        if current != text:
            print("server/api/admin_catalog.json is stale: run python tools/admin_catalog.py")
            return 1
        return 0
    with open(TARGET, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)
    print("wrote", os.path.relpath(TARGET, ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
