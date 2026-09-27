#!/usr/bin/env sh
set -eu
if [ "${RENEWED_LINEAGE:-}" = /etc/letsencrypt/live/gustfire.online ]; then
    /usr/bin/docker exec alocativa-nginx nginx -t
    /usr/bin/docker exec alocativa-nginx nginx -s reload
fi
