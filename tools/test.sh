#!/usr/bin/env bash
# The whole headless suite (every tests/*_tests.gd) on Linux, macOS or WSL.
#
#   tools/test.sh            import, then run every suite one after the other
#   tools/test.sh -j         run them in parallel (about as many as the CPU has cores)
#   tools/test.sh combat ui  only these suites (names without "_tests.gd")
#
# Godot comes from GODOT_BIN or the PATH. exchange_online_tests needs a running
# PostgreSQL API and stays out; run it by hand (docs/CAMBIO.md).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT_BIN:-$(command -v godot || true)}"
[ -x "$GODOT" ] || { echo "Godot not found: set GODOT_BIN to the Godot 4.7 executable." >&2; exit 2; }
PARALLEL=0
if [ "${1:-}" = "-j" ]; then PARALLEL=1; shift; fi

cd "$ROOT"
"$GODOT" --headless --path . --editor --import --quit > /dev/null 2>&1

if [ $# -gt 0 ]; then
  SUITES=("$@")
else
  mapfile -t SUITES < <(ls tests/*_tests.gd | xargs -n1 basename | sed 's/_tests.gd$//' | grep -vx 'exchange_online\|net\|net_e2e' | sort)
  SUITES+=(net net_e2e)
fi

LOGS="$(mktemp -d)"
run_one() {
  local name="$1"
  timeout 600 "$GODOT" --headless --path . --script "tests/${name}_tests.gd" > "$LOGS/$name.log" 2>&1
  echo $? > "$LOGS/$name.exit"
}

if [ "$PARALLEL" = 1 ]; then
  for name in "${SUITES[@]}"; do run_one "$name" & done
  wait
else
  for name in "${SUITES[@]}"; do echo "== $name"; run_one "$name"; done
fi

FAILED=0
for name in "${SUITES[@]}"; do
  code="$(cat "$LOGS/$name.exit" 2>/dev/null || echo 1)"
  line="$(grep -aE 'RESULT|checks:' "$LOGS/$name.log" | tail -1)"
  if [ "$code" != 0 ]; then FAILED=1; printf 'FAIL  %-12s %s\n' "$name" "$line"; grep -a '^ERROR' "$LOGS/$name.log" | head -5; else printf 'ok    %-12s %s\n' "$name" "$line"; fi
done
echo "logs: $LOGS"
exit $FAILED
