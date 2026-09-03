# Tailscale (optional, `TAILSCALE=1`)

Disabled by default. Runs the official `tailscale/tailscale` image with [`tailscale serve`](https://tailscale.com/kb/1242/tailscale-serve) configured for **L4 TCP forwarding** to nginx on port 4000. Access is **tailnet-only** — no public exposure, no port forwarding, no Cloudflare in the middle.

L4 mode means tailscale forwards the raw TCP stream straight to nginx without inspecting the Host header. nginx sees the original request — including Host, paths, everything — exactly as the client sent it. No FQDN config needed on the tailscale side.

State is bind-mounted at `${DATA_DIR_TAILSCALE:-${DATA_DIR:-.data}/tailscale}` so the node identity survives container recreates. After the first auth, the node stays logged in even if `TS_AUTHKEY` is rotated.

### Setup (hosted Tailscale)

1. Generate an auth key at [login.tailscale.com/admin/settings/keys](https://login.tailscale.com/admin/settings/keys) (reusable + ephemeral both work).
2. Set:

   ```env
   TAILSCALE=1
   TS_AUTHKEY=tskey-auth-...
   TS_HOSTNAME=aigate
   ```

3. `make run-bg`. The node joins your tailnet under `TS_HOSTNAME`.
4. From any tailnet-joined device: `http://aigate.tailXXXX.ts.net` → aigate's nginx.

Find your tailnet name with `docker compose exec tailscale tailscale status` after first connect.

### Setup (Headscale or other custom control server)

Add `--login-server` to `TS_EXTRA_ARGS`:

```env
TAILSCALE=1
TS_AUTHKEY=hskey-auth-...
TS_HOSTNAME=aigate
TS_EXTRA_ARGS=--login-server=https://your-headscale.example.com
```

The FQDN your tailnet exposes (`aigate.<base_domain>`) is determined by your Headscale's `base_domain` setting — nothing to configure on the aigate side.

### Custom port

Default forward port is 80 (`http://<host>.<tailnet>/`). Change with `TS_SERVE_PORT=8080` etc.

### Notes

- L4 forwarding means HTTPS auto-cert (Tailscale's hosted ACME proxy) is **not** in play here — TLS termination, if you want it, lives in nginx. Easier to keep it as plain HTTP over the tailnet, which is already encrypted by WireGuard.
- The container needs `NET_ADMIN`, `NET_RAW`, and `/dev/net/tun` for kernel networking.
- Forwarding sysctls (`net.ipv4.ip_forward=1`, `net.ipv6.conf.all.forwarding=1`) are set so subnet-routing and exit-node modes work if you add `--advertise-routes=...` or `--advertise-exit-node` via `TS_EXTRA_ARGS`.
- Stays on the `aigate-public` network so the `nginx:4000` upstream resolves via Docker DNS.

### Tailnet egress for claudebox and pibox-zai

`tailscale serve` covers the inbound direction: tailnet devices reaching aigate. The reverse, letting the agent containers reach machines on your tailnet, is off by default and turns on when `TAILSCALE=1` runs alongside `CLAUDEBOX=1` or `PIBOX_ZAI=1`. The Makefile then loads the `docker-compose.tailscale.yml` overlay, which routes tailnet traffic out through the existing tailscale node. Both containers stay on the bridge, so nginx and LiteLLM still reach them as before.

With the overlay active, from inside claudebox or pibox-zai you can resolve tailnet names and connect to tailnet peers over any protocol (SSH, HTTP, whatever the peer serves), while container names and public names keep resolving as usual.

How it works:

- The tailscale container becomes a NAT gateway for the tailnet CGNAT range. A small sidecar keeps a `MASQUERADE` rule on `tailscale0` so replies find their way back to the bridge clients.
- Each agent container gets a route for `100.64.0.0/10` (the range Tailscale assigns every node) pointed at the tailscale container. A per-container sidecar sharing that container's network namespace installs the route and re-adds it after a restart, since Compose has no static-route field.
- DNS is split. Tailscale MagicDNS (`100.100.100.100`) answers tailnet names and returns SERVFAIL for everything else; Docker's embedded resolver falls through to a public resolver for public names and still answers sibling container names.

Two settings, both optional:

```env
# Your tailnet's MagicDNS suffix, from `tailscale status` (hosted: tailXXXX.ts.net;
# Headscale: your base_domain). Lets the containers resolve bare tailnet names in
# addition to FQDNs. Leave unset to require fully-qualified names.
TS_MAGICDNS_SUFFIX=tailXXXX.ts.net

# Resolver for non-tailnet names, since MagicDNS only answers tailnet names.
# Defaults to 1.1.1.1; set your own to keep public DNS on your infrastructure.
TS_FALLBACK_DNS=1.1.1.1
```

Scope and limits:

- Covers IPv4 tailnet peers by their `100.64.0.0/10` address or MagicDNS name. That is the complete range for node-to-node tailnet access.
- A LAN behind a subnet router is **not** in `100.64.0.0/10`, so it is not reached by this route. Add that subnet as a separate route if you need it.
- IPv4 only. Tailnet IPv6 (`fd7a:115c:a1e0::/48`) is not routed.
- The egress sidecars carry `no-new-privileges:true` and `cap_drop: [ALL]`, adding back only `NET_ADMIN` (and `NET_RAW` on the gateway sidecar for the NAT rule).

---

