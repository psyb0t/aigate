FROM cloudflare/cloudflared:latest AS src
FROM alpine:3.21
COPY --from=src /usr/local/bin/cloudflared /usr/local/bin/cloudflared
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
