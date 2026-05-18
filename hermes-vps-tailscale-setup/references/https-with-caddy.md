# Optional: HTTPS on custom ports with Caddy + `tailscale cert`

Only use this when the user explicitly asks for `https://<host>.<tailnet>.ts.net:<PORT>/` to work in a browser without warnings. For Tailscale-only internal dashboards, plain HTTP is usually fine because WireGuard already encrypts the path.

## Prerequisites

- Tailscale admin console has **HTTPS Certificates** enabled.
- The VPS can issue a cert for its own tailnet hostname: `tailscale cert <host>.<tailnet>.ts.net` (run as root or under sudo). Certs land in `./<host>.<tailnet>.ts.net.crt` and `.key` and are renewable the same way.

## Design

Keep each app listening on `127.0.0.1:<PORT>` (the Hermes default; no `--insecure` needed). Run Caddy as a local reverse proxy that listens on the Tailscale IP for every desired port and terminates TLS there. Per-port HTTPS without taking over 443.

```text path=null start=null
Browser ─HTTPS→ 100.x.y.z:9119 (Caddy) ─HTTP→ 127.0.0.1:9119 (hermes dashboard)
Browser ─HTTPS→ 100.x.y.z:9200 (Caddy) ─HTTP→ 127.0.0.1:9200 (gaming dashboard)
```

## Example `Caddyfile`

Place at `/etc/caddy/Caddyfile` (or run via `caddy run` under a systemd-user unit, matching the rest of this skill):

```caddyfile path=null start=null
{
  # Disable Caddy's automatic public ACME; we'll supply Tailscale-issued certs.
  auto_https off
}

# Shared cert for the tailnet hostname.
(tls_ts) {
  tls /etc/caddy/tls/<TAILSCALE_DOMAIN>.ts.net.crt \
      /etc/caddy/tls/<TAILSCALE_DOMAIN>.ts.net.key
}

https://<TAILSCALE_DOMAIN>.ts.net:9119 {
  import tls_ts
  reverse_proxy 127.0.0.1:9119
}

https://<TAILSCALE_DOMAIN>.ts.net:9200 {
  import tls_ts
  reverse_proxy 127.0.0.1:9200
}
```

## Cert refresh

`tailscale cert` certs have ~90-day validity like Let's Encrypt. Automate renewal with a user cron or a systemd-user timer:

```bash path=null start=null
# ~/bin/refresh-ts-cert.sh
sudo tailscale cert \
  --cert-file /etc/caddy/tls/<TAILSCALE_DOMAIN>.ts.net.crt \
  --key-file  /etc/caddy/tls/<TAILSCALE_DOMAIN>.ts.net.key \
  <TAILSCALE_DOMAIN>.ts.net
sudo systemctl reload caddy
```

Run monthly; Tailscale will 304-style skip unless close to expiry.

## Binding address for Caddy

If the user wants to avoid Caddy listening on `0.0.0.0` (and thus on the public NIC), bind Caddy to the Tailscale IP:

```caddyfile path=null start=null
{
  auto_https off
  default_bind <TAILSCALE_IP>
}
```

Adjust on a per-host basis, or compute at deploy time using `tailscale ip -4`.

## Reverting to plain HTTP

Disable the Caddy service, reconfigure each app to bind `--host $(tailscale ip -4 | head -1)` directly on its public port (as in the main `SKILL.md`), and you're back to the simple pattern.

## When *not* to use this

- The user just wants quick internal access: plain HTTP over Tailscale is simpler and equally private.
- The browser APIs the user needs don't require a secure context.
- There's only one dashboard and `tailscale serve --https=443` (no port in URL) is acceptable.
