#!/usr/bin/env bash
set -euo pipefail
deploy=/home/ubuntu/frontierTank/.deploy
conf=/home/ubuntu/alocativateam/al-infra/nginx/conf.d/zz-gustfire.conf

test -s "$deploy/api.env"
test "$(stat -c %a "$deploy/api.env")" = 600
docker compose -f "$deploy/compose.api.yaml" up -d

ready=0
for attempt in $(seq 1 30); do
    if docker exec frontier-tank-web wget -q -T 5 -O /dev/null http://frontier-api:8080/v1/health; then
        ready=1
        break
    fi
    sleep 2
done
if [ "$ready" != 1 ]; then
    echo 'API did not become healthy; inspect the container logs.' >&2
    exit 1
fi
python3 "$deploy/verify-gustfire-db.py"
cp "$conf" "$deploy/nginx-before-api.conf"
cp "$deploy/gustfire-https.nginx.conf" "$conf"
if ! docker exec alocativa-nginx nginx -t; then
    cp "$deploy/nginx-before-api.conf" "$conf"
    exit 1
fi
docker exec alocativa-nginx nginx -s reload
curl --fail --silent --show-error https://gustfire.online/v1/health
echo
docker ps --filter name=frontier-tank-api --format '{{.Names}} {{.Status}}'
