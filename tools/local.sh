#!/usr/bin/env bash
# Frontier Tank on this machine: PostgreSQL, the API, the game server and the web game,
# with Docker (server/docker-compose.yml). The same script runs the stack on a VM.
#
#   tools/local.sh            build and start everything, wait until it answers and open
#                             http://localhost:8000 (the first build takes a few minutes)
#   tools/local.sh status     what is running and the game servers the API lists
#   tools/local.sh logs [svc] follow the logs (api, game, web, db)
#   tools/local.sh stop       stop (the game server saves every profile first)
#   tools/local.sh reset      stop and ERASE the database (asks first)
#
# The first run creates server/.env from server/.env.example with random secrets and the
# test coupons on (closed tests). Edit server/.env and run again to change anything.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT/server/.env"
COMPOSE=(docker compose -f "$ROOT/server/docker-compose.yml")

setting() {
	# A value of server/.env (or the default).
	local value
	value="$(grep -E "^$1=" "$ENV_FILE" 2>/dev/null | tail -1 | cut -d= -f2- || true)"
	echo "${value:-$2}"
}

secret() {
	head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n'
}

make_env() {
	[ -f "$ENV_FILE" ] && return
	echo "Creating server/.env (random password and key, test coupons on)"
	sed -e "s/^DB_PASSWORD=.*/DB_PASSWORD=$(secret)/" \
		-e "s/^INTERNAL_KEY=.*/INTERNAL_KEY=$(secret)/" \
		-e "s/^TEST_COUPONS=.*/TEST_COUPONS=1/" \
		-e "s/^BOT_FILL_SECONDS=.*/BOT_FILL_SECONDS=8/" \
		"$ROOT/server/.env.example" > "$ENV_FILE"
	chmod 600 "$ENV_FILE"
}

wait_ready() {
	local url="http://localhost:$(setting WEB_PORT 8000)"
	echo -n "Waiting for the game server to show up at $url "
	for _ in $(seq 1 120); do
		if curl -fsS "$url/v1/servers" 2>/dev/null | grep -q '"url"'; then
			echo
			echo "Ready: $url"
			return 0
		fi
		echo -n "."
		sleep 2
	done
	echo
	echo "Still not answering after 4 minutes. See: tools/local.sh logs" >&2
	return 1
}

open_browser() {
	local url="http://localhost:$(setting WEB_PORT 8000)"
	if command -v xdg-open > /dev/null && [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
		xdg-open "$url" > /dev/null 2>&1 || true
	elif command -v open > /dev/null && [ "$(uname)" = "Darwin" ]; then
		open "$url"
	fi
}

command -v docker > /dev/null || { echo "Docker is not installed (https://docs.docker.com/engine/install/)." >&2; exit 1; }
docker compose version > /dev/null 2>&1 || { echo "Docker Compose v2 is missing (docker compose)." >&2; exit 1; }

case "${1:-up}" in
	up)
		make_env
		"${COMPOSE[@]}" up --build -d
		wait_ready
		open_browser
		;;
	status)
		"${COMPOSE[@]}" ps
		curl -fsS "http://localhost:$(setting WEB_PORT 8000)/v1/servers" && echo || echo "The API does not answer on the web port."
		;;
	logs)
		shift
		"${COMPOSE[@]}" logs -f --tail 100 "$@"
		;;
	stop)
		"${COMPOSE[@]}" stop
		;;
	reset)
		read -r -p "Erase every account, profile and listing? Type APAGAR: " answer
		[ "$answer" = "APAGAR" ] || { echo "Nothing erased."; exit 0; }
		"${COMPOSE[@]}" down -v
		;;
	*)
		sed -n '2,13p' "$0"
		exit 1
		;;
esac
