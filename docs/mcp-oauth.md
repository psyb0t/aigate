# MCP OAuth and proxy setup

Bearer-key clients keep using `/mcp/`. OAuth is optional and configured in the LiteLLM admin UI for the server or client that needs it. An upgrade does not authorize outside accounts.

## Choose the browser-facing URL

Set the origin you actually open in your browser in the gitignored `.env`:

```env
PROXY_BASE_URL=https://aigate.example.com
```

The hostname can be private. Your browser must reach it over HTTPS. `http://localhost:4000` works for loopback testing on the browser machine, but a remote server's localhost or a Docker service name is not a browser callback. Plain HTTP on a remote tailnet hostname does not satisfy HTTPS OAuth checks.

Use a fixed TLS hostname through a named Cloudflare tunnel or your own reverse proxy. Public DNS and port forwarding are not requirements for a private setup. Keep the origin unchanged throughout authorization.

Run `make run-bg` after changing `.env`. Open `$PROXY_BASE_URL/ui/`, sign in, and configure the MCP transport, OAuth settings and client registration required by that provider. Register the exact redirect URL shown by LiteLLM. The UI callback uses `/ui/mcp/oauth/callback`; desktop clients can have permitted loopback or native callbacks of their own. Complete authorization in the browser, list tools, and call one as that authorized identity. Never put access or refresh tokens in tracked configuration.

## Check discovery

```bash
curl -fsS "$PROXY_BASE_URL/.well-known/oauth-authorization-server" | jq '{issuer, authorization_endpoint, token_endpoint}'
```

The issuer must match the configured origin. A redirect rejection or insecure-cookie problem usually means the browser URL and `PROXY_BASE_URL` differ. Inspect logs without publishing authorization codes or tokens. For a separate-origin OAuth client, `MCP_TRUSTED_REDIRECT_ORIGINS` allows its specific origin; do not use a wildcard.

## Network trust

`aigate-ingress` contains nginx and enabled Cloudflare/Tailscale edges. `aigate-proxy` contains nginx and LiteLLM. nginx accepts a forwarded client address only from the ingress network, replaces outgoing address/host/scheme headers and clears forwarded-port and `Forwarded` headers. LiteLLM trusts only the dedicated nginx hop and reads the rightmost sanitized address. Tailnet `100.64.0.0/10` addresses count as internal. Bearer authentication still applies.

Defaults are `172.30.255.232/29` for ingress and `172.30.255.240/29` for the proxy hop. Change `AIGATE_INGRESS_SUBNET` and `AIGATE_PROXY_SUBNET` in `.env` if they overlap existing routes. Each must be a private IPv4 CIDR between `/24` and `/29`; they must not overlap each other. Do not attach untrusted services to these networks or trust every Docker/private address.

Named Cloudflare tunnels target `http://nginx-edge:4000`. Tailscale uses an HTTP proxy; Headscale users set `TS_SERVE_FQDN` to their actual node hostname. Another reverse proxy must join the ingress network and replace incoming forwarding headers with real connection metadata. Direct clients on port 4000 cannot choose their own trusted IP.

## Upgrade

After pulling, set `TS_SERVE_FQDN` when required and update any named tunnel target to `nginx-edge:4000`. Run `make restart-gateway` to regenerate the config and recreate Redis, LiteLLM, nginx, enabled edges and active Tailscale egress helpers. Redis retains its bind-mounted data. No CUDA rebuild or model download is needed. Back up persistent state before upgrading.

The Redis ACL allows publish/subscribe only on `aigate:cache:litellm_proxy.auth_cache_invalidation` and `aigate:cache:litellm_proxy.config_change`, so management updates that LiteLLM broadcasts reach other workers. Unrelated channels, queue keys, admin commands and flushes remain denied.

LiteLLM 1.104.0 does not broadcast token-cache eviction on `/key/delete`. Aigate therefore sets `general_settings.user_api_key_cache_ttl: 0`: virtual-key authorization reads PostgreSQL instead of retaining per-worker authorization objects. This costs extra database reads but prevents deleted keys from remaining valid on another worker. Model-response caching keeps its existing 10-minute TTL. Do not restore a positive auth-cache TTL until cross-worker deletion tests pass against an upstream fix.
