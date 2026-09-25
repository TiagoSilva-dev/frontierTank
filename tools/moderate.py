#!/usr/bin/env python3
"""Review chat reports (launch checklist: moderated chat).

The reports live in the API (PostgreSQL, table chat_reports) and are reached through the
internal port (8081), which only the game servers and the team use: run this on the
server machine, or through an SSH tunnel (ssh -L 8081:localhost:8081 ...).

Usage:
  python tools/moderate.py list [--status open|dismissed|warned|banned] [--limit 50]
  python tools/moderate.py review <id> dismissed|warned|banned --reviewer <name> [--note "..."]

  --internal http://localhost:8081   internal API address (or FT_INTERNAL_API)
  --key <INTERNAL_KEY>               internal key (or FT_INTERNAL_KEY)

"banned" suspends the reported account (it can no longer log in) and ends its sessions.
"warned" only records the decision: tell the player through the support e-mail.
"""
import argparse
import json
import os
import sys
import urllib.error
import urllib.request

REASONS = {
    "ofensa": "ofensa, ameaça ou assédio",
    "odio": "discurso de ódio ou discriminação",
    "spam": "spam ou propaganda",
    "golpe": "golpe ou venda por dinheiro",
    "dados": "expõe dados pessoais",
    "nome": "nome de personagem ofensivo",
    "outro": "outro motivo",
}


def call(args, method, path, body=None):
    data = None if body is None else json.dumps(body).encode()
    request = urllib.request.Request(args.internal.rstrip("/") + path, data=data, method=method, headers={"X-Internal-Key": args.key, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=15) as reply:
            text = reply.read().decode()
            return reply.status, json.loads(text) if text else {}
    except urllib.error.HTTPError as error:
        text = error.read().decode()
        return error.code, json.loads(text) if text.startswith("{") else {"error": text}


def cmd_list(args):
    status, reply = call(args, "GET", f"/internal/reports?status={args.status}&limit={args.limit}")
    if status != 200:
        sys.exit(f"Error {status}: {reply}")
    reports = reply.get("reports", [])
    if not reports:
        print(f"No {args.status} reports.")
    for report in reports:
        who = report["reported_name"] or "(deleted account)"
        print(f"#{report['id']}  {report['created_at'][:19]}  {report['server_id']}  {who} (account {report['reported_id']})")
        print(f"    reason: {REASONS.get(report['reason'], report['reason'])}" + ("   [auto-muted]" if report["auto_muted"] else "") + f"   other reports in 30 days: {report['previous']}")
        print(f"    by: {report['reporter_name'] or '(deleted account)'}" + (f"   note: {report['note']}" if report["note"] else ""))
        for line in report.get("context") or []:
            mark = ">>" if line.get("reported") else "  "
            print(f"    {mark} {line.get('author', '')}: {line.get('text', '')}")
        if report["status"] != "open":
            print(f"    {report['status']} by {report['reviewer']}: {report['review_note']}")
        print()


def cmd_review(args):
    status, reply = call(args, "POST", f"/internal/reports/{args.id}/review", {"status": args.decision, "reviewer": args.reviewer, "note": args.note})
    if status != 204:
        sys.exit(f"Error {status}: {reply}")
    print(f"Report #{args.id}: {args.decision}.")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--internal", default=os.environ.get("FT_INTERNAL_API", "http://localhost:8081"))
    parser.add_argument("--key", default=os.environ.get("FT_INTERNAL_KEY", ""))
    commands = parser.add_subparsers(dest="command", required=True)
    listing = commands.add_parser("list")
    listing.add_argument("--status", default="open", choices=["open", "dismissed", "warned", "banned"])
    listing.add_argument("--limit", type=int, default=50)
    review = commands.add_parser("review")
    review.add_argument("id", type=int)
    review.add_argument("decision", choices=["dismissed", "warned", "banned"])
    review.add_argument("--reviewer", required=True)
    review.add_argument("--note", default="")
    args = parser.parse_args()
    if not args.key:
        sys.exit("Set --key or FT_INTERNAL_KEY (the INTERNAL_KEY of server/.env).")
    {"list": cmd_list, "review": cmd_review}[args.command](args)


if __name__ == "__main__":
    main()
