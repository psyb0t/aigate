# Cloudflared (optional, `CLOUDFLARED=1`)

Disabled by default. Enable by setting `CLOUDFLARED=1` in `.env`.

### Quick tunnel (no account needed)

```env
CLOUDFLARED=1
```

Cloudflare assigns a random `*.trycloudflare.com` URL and logs it on startup:

```bash
docker compose up -d
docker compose logs cloudflared | grep trycloudflare
```

### Named tunnel (fixed domain, requires Cloudflare account)

```env
CLOUDFLARED=1
CLOUDFLARED_CONFIG=/absolute/path/to/config.yml
CLOUDFLARED_CREDS=/absolute/path/to/credentials.json
```

Example `config.yml`:

```yaml
tunnel: <your-tunnel-id>
credentials-file: /etc/cloudflared/credentials.json
ingress:
  - hostname: aigate.yourdomain.com
    service: http://nginx-edge:4000
  - service: http_status:404
```

Get your tunnel ID and credentials: [Cloudflare Tunnel guide](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/get-started/)

Use `nginx-edge:4000` in existing named-tunnel configurations too. This alias resolves only on the dedicated ingress network, where nginx trusts the forwarded client IP. Keep tunnel configuration and credentials outside Git.

For browser-based MCP authorization, set `PROXY_BASE_URL` to the fixed HTTPS origin. See [MCP OAuth setup](../mcp-oauth.md).

---

