#!/usr/bin/env bash
set -euo pipefail

project=/home/ubuntu/frontierTank
conf=/home/ubuntu/alocativateam/al-infra/nginx/conf.d
webroot="$conf/gustfire-acme"

for domain in gustfire.online www.gustfire.online; do
    if ! dig @1.1.1.1 +short "$domain" A | grep -Fxq '136.248.73.212'; then
        echo "DNS publico de $domain ainda nao aponta para a VM. Tente apos a propagacao." >&2
        exit 2
    fi
done

sudo certbot certonly --webroot -w "$webroot" \
    --cert-name gustfire.online -d gustfire.online -d www.gustfire.online \
    --non-interactive --keep-until-expiring

cp "$conf/zz-gustfire.conf" "$project/.deploy/gustfire-before-https.conf"
cp "$project/.deploy/gustfire-https.nginx.conf" "$conf/zz-gustfire.conf"
if ! docker exec alocativa-nginx nginx -t; then
    cp "$project/.deploy/gustfire-before-https.conf" "$conf/zz-gustfire.conf"
    exit 1
fi
docker exec alocativa-nginx nginx -s reload

sudo install -m 755 "$project/.deploy/gustfire-renew-hook.sh" \
    /etc/letsencrypt/renewal-hooks/deploy/gustfire-reload
sudo systemctl enable --now certbot.timer
curl --fail --silent --show-error --head https://gustfire.online/jogar/
