#!/bin/sh
set -e

if [ -s /etc/cloudflared/config.yml ]; then
    exec cloudflared --no-autoupdate tunnel --config /etc/cloudflared/config.yml run
else
    echo "cloudflared: no config mounted — starting quick tunnel (random trycloudflare.com URL)"
    exec cloudflared --no-autoupdate tunnel --url http://nginx:4000
fi
