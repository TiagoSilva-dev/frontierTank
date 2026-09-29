#!/bin/sh
set -eu

if [ -z "${DNS_RESOLVER:-}" ]; then
	DNS_RESOLVER="$(awk '$1 == "nameserver" { print $2; exit }' /etc/resolv.conf)"
fi
case "$DNS_RESOLVER" in
	*:*) DNS_RESOLVER="[$DNS_RESOLVER]" ;;
esac
: "${API_HOST:=api}"
: "${GAME_HOST:=game}"
export API_HOST GAME_HOST DNS_RESOLVER

exec /docker-entrypoint.sh nginx -g 'daemon off;'