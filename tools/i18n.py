#!/usr/bin/env python3
"""Collect the game's texts into locale/messages.pot and keep locale/en.po in sync.

Portuguese is the source language: every visible text is its own key (gettext style).
Keys come from
  * tr("...") and Lang.t("...") calls in client/**/*.gd and server/game/*.gd (the
    game server sends these texts as keys and the players translate them; the literal
    must be the whole
    argument; format it after the call: tr("%d moedas") % coins),
  * every string literal on a line that ends with "# i18n" (constant tables),
  * the "name", "desc", "text", "label", "attack" and "fury_name" fields of
    shared/balance/*.json.

Usage:
  python tools/i18n.py                 update messages.pot and en.po (new keys get an
                                       empty msgstr, keys no longer used are dropped)
  python tools/i18n.py --import f.json merge {"pt text": "en text"} into en.po first
  python tools/i18n.py --missing       list keys without English text
  python tools/i18n.py --check         exit 1 if the .pot is stale or en.po is incomplete
"""
import glob
import json
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
POT = os.path.join(ROOT, "locale", "messages.pot")
PO = os.path.join(ROOT, "locale", "en.po")
JSON_KEYS = {"name", "desc", "text", "label", "attack", "fury_name"}
LITERAL = r'"((?:[^"\\]|\\.)*)"'
CALL = re.compile(r'(?:\btr|\bLang\.t)\(\s*' + LITERAL + r'\s*\)')
ANY = re.compile(LITERAL)


def gd_unescape(text):
    out, i = [], 0
    while i < len(text):
        ch = text[i]
        if ch == "\\" and i + 1 < len(text):
            nxt = text[i + 1]
            if nxt == "u":
                out.append(chr(int(text[i + 2:i + 6], 16)))
                i += 6
                continue
            out.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\", "'": "'"}.get(nxt, nxt))
            i += 2
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def po_escape(text):
    return text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t")


def po_unescape(text):
    return gd_unescape(text)


def code_comment_start(line):
    quoted = False
    for i, ch in enumerate(line):
        if ch == '"' and (i == 0 or line[i - 1] != "\\"):
            quoted = not quoted
        elif ch == "#" and not quoted:
            return i
    return -1


def collect():
    found = {}

    def add(text, ref):
        if text.strip() == "" or not re.search(r"[A-Za-zÀ-ÿ]", text):
            return
        found.setdefault(text, [])
        if ref not in found[text]:
            found[text].append(ref)

    for path in sorted(glob.glob(os.path.join(ROOT, "client", "**", "*.gd"), recursive=True) + glob.glob(os.path.join(ROOT, "server", "game", "*.gd"))):
        rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
        for number, line in enumerate(open(path, encoding="utf-8"), 1):
            cut = code_comment_start(line)
            code = line if cut < 0 else line[:cut]
            marked = cut >= 0 and line[cut:].strip().startswith("# i18n")
            for match in (ANY if marked else CALL).finditer(code):
                text = gd_unescape(match.group(1))
                # On "# i18n" lines ids, paths and colours stay out.
                if marked and (re.fullmatch(r"[a-z0-9_]+|[0-9a-fA-F]{6,8}", text) or text.startswith("res://")):
                    continue
                add(text, "%s:%d" % (rel, number))
    for path in sorted(glob.glob(os.path.join(ROOT, "shared", "balance", "*.json"))):
        rel = os.path.relpath(path, ROOT).replace(os.sep, "/")

        def walk(node, trail):
            if isinstance(node, dict):
                for key, value in node.items():
                    if key in JSON_KEYS and isinstance(value, str):
                        add(value, "%s:%s.%s" % (rel, trail, key))
                    else:
                        walk(value, "%s.%s" % (trail, key) if trail else key)
            elif isinstance(node, list):
                for i, value in enumerate(node):
                    walk(value, "%s[%d]" % (trail, i))
        walk(json.load(open(path, encoding="utf-8")), "")
    return found


def read_po(path):
    entries = {}
    if not os.path.exists(path):
        return entries
    msgid = msgstr = None
    target = None
    for raw in open(path, encoding="utf-8"):
        line = raw.strip()
        if line.startswith("msgid "):
            if msgid is not None:
                entries[msgid] = msgstr
            msgid, msgstr, target = po_unescape(line[7:-1]), "", "id"
        elif line.startswith("msgstr "):
            msgstr, target = po_unescape(line[8:-1]), "str"
        elif line.startswith('"') and target:
            if target == "id":
                msgid += po_unescape(line[1:-1])
            else:
                msgstr += po_unescape(line[1:-1])
        elif line == "" or line.startswith("#"):
            continue
    if msgid is not None:
        entries[msgid] = msgstr
    entries.pop("", None)
    return entries


HEADER = '''msgid ""
msgstr ""
"Project-Id-Version: Frontier Tank\\n"
"MIME-Version: 1.0\\n"
"Content-Type: text/plain; charset=UTF-8\\n"
"Content-Transfer-Encoding: 8bit\\n"
%s
'''


def write(path, found, translations, language):
    lines = [HEADER % ('"Language: %s\\n"' % language if language else '"Language: \\n"')]
    for text in sorted(found, key=lambda t: (found[t][0], t)):
        lines.append("#: %s" % " ".join(found[text][:4]))
        lines.append('msgid "%s"' % po_escape(text))
        lines.append('msgstr "%s"' % po_escape(translations.get(text, "") if translations is not None else ""))
        lines.append("")
    with open(path, "w", encoding="utf-8", newline="\n") as out:
        out.write("\n".join(lines))


def main():
    found = collect()
    current = read_po(PO)
    if "--import" in sys.argv:
        extra = json.load(open(sys.argv[sys.argv.index("--import") + 1], encoding="utf-8"))
        current.update({k: v for k, v in extra.items() if v})
    missing = [text for text in found if not current.get(text)]
    if "--check" in sys.argv:
        stale = set(read_po(POT)) != set(found)
        if stale:
            print("locale/messages.pot is out of date: run python tools/i18n.py")
        for text in missing:
            print("missing English: %r" % text)
        sys.exit(1 if stale or missing else 0)
    if "--missing" in sys.argv:
        for text in missing:
            print(json.dumps(text, ensure_ascii=False))
        print("%d of %d keys without English" % (len(missing), len(found)), file=sys.stderr)
        return
    os.makedirs(os.path.dirname(POT), exist_ok=True)
    write(POT, found, None, "")
    write(PO, found, current, "en")
    dropped = [text for text in current if text not in found]
    print("%d keys, %d without English, %d unused dropped" % (len(found), len(missing), len(dropped)))


if __name__ == "__main__":
    main()
