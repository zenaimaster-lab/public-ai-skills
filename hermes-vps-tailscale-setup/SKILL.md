---
name: hermes-vps-tailscale-setup
description: Configure a Hermes Agent VPS so its local web dashboards (e.g., :9119, :9200) are reachable from a laptop over Tailscale using the pattern http://<host>.<tailnet>.ts.net:<port>/, persist the service across reboots, and diagnose the common failures along the way. Use this skill whenever the user wants to expose Hermes Agent Dashboard or any localhost-bound dashboard/service on a VPS to their tailnet, mentions connecting to a Hermes/VPS dashboard from their Mac, reports ERR_CONNECTION_REFUSED / "refused to connect" on a *.ts.net address, asks about binding to Tailscale IP vs 0.0.0.0 vs 127.0.0.1, hits "Web UI frontend not built and npm is not available" when starting `hermes dashboard` via SSH, or wants to repeat this setup on additional Hermes VPS hosts. Also use it when the user asks why HTTPS doesn't work on a non-standard port on their tailnet.
---

# Hermes VPS Tailscale Dashboard Setup

Goal: make `http://<hostname>.<tailnet>.ts.net:<PORT>/` reach a localhost-only dashboard (Hermes or similar) on a VPS, cleanly and persistently, using the user's existing Tailscale mesh.

This skill captures the full diagnosis and the exact commands needed so the same procedure can be applied to new Hermes VPS hosts without rediscovering the pitfalls.

## Mental model — why the default setup fails

Three IP layers live on a Hermes VPS:

- `127.0.0.1` (loopback) — the default bind for `hermes dashboard`; only processes on the same box can connect.
- `100.x.y.z` on `tailscale0` — the address peers use when resolving `<host>.<tailnet>.ts.net` via MagicDNS.
- Public IP on `eth0` — the internet-facing NIC.

When a browser on the laptop opens `http://<host>.<tailnet>.ts.net:<PORT>/`, the packet arrives on `tailscale0` with destination `100.x.y.z:<PORT>`. If the dashboard only listens on `127.0.0.1:<PORT>`, the kernel has no socket at that address and returns `TCP RST`, which the browser shows as `ERR_CONNECTION_REFUSED`. This is a **bind-address problem**, not a Tailscale or firewall problem.

The safe fix is to bind the dashboard **specifically to the Tailscale IP**, not to `0.0.0.0`. Binding to `0.0.0.0` also opens the dashboard on the public NIC — a real risk because Hermes dashboards hold API keys (which is why `hermes dashboard` requires an `--insecure` flag to leave loopback).

## Prerequisites (verify first)

Connect to the VPS via the user's declared SSH entry point, then confirm:

1. `tailscale status` shows the VPS peered with the user's laptop; record the VPS Tailscale IPv4 with `tailscale ip -4`.
2. `which node && which npm` from a **login shell** (`bash -lc 'which npm'`). On Hermes VPS these usually live in `~/.local/bin` via `.bashrc`/`.profile`.
3. `loginctl show-user $USER | grep Linger` — `Linger=yes` means systemd user services survive disconnect/reboot. If missing, run `sudo loginctl enable-linger $USER`.
4. The dashboard was started at least once so the installation and web source (`~/.hermes/hermes-agent/web`) exist.

## Setup procedure

### 1. Create a PATH-aware launcher script

`~/start-hermes-dashboard.sh`:

```bash path=null start=null
#!/bin/bash
# PATH must include ~/.local/bin so `npm`/`node` are visible to the dashboard's
# web-UI build step. Without this, `hermes dashboard` exits immediately with
# "Web UI frontend not built and npm is not available."
export PATH=$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

TS_IP=$(tailscale ip -4 | head -1)

cd "$HOME"
exec "$HOME/.hermes/hermes-agent/venv/bin/python3" \
     "$HOME/.local/bin/hermes" dashboard \
     --host "$TS_IP" \
     --port 9119 \
     --insecure \
     --no-open
```

Make executable: `chmod +x ~/start-hermes-dashboard.sh`.

Key flags:
- `--host "$TS_IP"` — binds only to `tailscale0`; impossible to hit from the public internet even if a cloud firewall is misconfigured.
- `--insecure` — required by `hermes dashboard` to accept any `--host` other than loopback. The name sounds scary but the traffic path is still fully encrypted by WireGuard.
- `--no-open` — no X display on a headless VPS; prevents the process from trying to `xdg-open` a browser.

### 2. Stop any foreground instance, then launch as a user-scoped systemd unit

Running from SSH directly (e.g., `nohup ... &`) often fails on these VPSs because SSH closes the session before the backgrounded process detaches cleanly (exit 255 symptoms). Use `systemd-run --user` instead; it's transient, lingering, and decoupled from the SSH pty.

Important: **run `systemd-run` in its own, minimal SSH invocation**. Do NOT chain it into a compound remote command like `pkill ...; systemd-run ...; systemctl status ...` inside a single `ssh user@host '...'` call — empirically this causes the remote shell to return exit 255 after the `pkill`/script-write step and `systemd-run` is silently skipped (the unit later shows up as "could not be found"). Keep the dashboard-launch SSH call to exactly one command with no extra `pkill`, no tail `echo`, no status check. Verification happens in a separate SSH call below.

Also prefer absolute paths (`/home/<user>/start-hermes-dashboard.sh`) over `$HOME` in the launch command — `$HOME` must survive the client-side shell, sshpass, and the remote shell, and nested quoting is easy to get wrong.

On a fresh box (no prior dashboard running), skip the `pkill` entirely. Only run it when Step 3 below shows a stray listener on `127.0.0.1:<PORT>`.

```bash path=null start=null
# On the VPS (one SSH call, nothing else in the same command):
systemd-run --user --unit=hermes-dashboard --same-dir \
  --setenv=PATH=/home/<user>/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  /home/<user>/start-hermes-dashboard.sh
```

Management:

```bash path=null start=null
systemctl --user status  hermes-dashboard
systemctl --user restart hermes-dashboard
systemctl --user stop    hermes-dashboard
journalctl --user -u hermes-dashboard -f   # live logs
```

On first start the dashboard runs `npm install && npm run build` for the web UI. Expect 30–60 s before the listener is up.

### 3. Verify

On the VPS:

```bash path=null start=null
ss -tlnp | grep :9119
# Expect: LISTEN  100.x.y.z:9119  users:(("python3",pid=...))
curl -sSf -o /dev/null -w "%{http_code}\n" "http://$(tailscale ip -4 | head -1):9119/"
# Expect: 200
```

From the laptop:

```bash path=null start=null
dig +short <host>.<tailnet>.ts.net          # must resolve to the VPS tailscale IP
curl -sSf -o /dev/null -w "%{http_code}\n" http://<host>.<tailnet>.ts.net:9119/
# Expect: 200
```

Then open `http://<host>.<tailnet>.ts.net:9119/` in the browser.

## Firewall hygiene on the cloud provider

The only inbound rules needed at the cloud-provider firewall for this pattern are:

- **UDP 41641** — Tailscale (the WireGuard port; a lower port may be negotiated but 41641 is the default).
- **TCP** for the SSH port in use (e.g., 1404).

Do **not** open TCP ports for dashboards (9119, 9200, …) on the public firewall. The traffic reaches the dashboard via `tailscale0` after WireGuard decapsulation; it does not pass the cloud firewall again. A UDP rule on a dashboard port (e.g., `UDP 9119`) is a no-op because HTTP is TCP — delete it to reduce confusion.

## Adding more dashboards (e.g., Gaming :9200)

Reuse the pattern. For each new app:

1. Make sure the app supports a bind-address flag. Bind it to `$(tailscale ip -4 | head -1)` on the desired port.
2. Clone `start-hermes-dashboard.sh` to `start-<app>.sh`, change the command and port.
3. Launch with `systemd-run --user --unit=<app> ...`.
4. Access: `http://<host>.<tailnet>.ts.net:<PORT>/`.

No firewall changes, no DNS changes.

## About HTTPS

HTTPS on a custom port like `:9119` is not available out of the box:

- Tailscale issues valid certs for `<host>.<tailnet>.ts.net`, but only `tailscale serve` / `tailscale funnel` terminate TLS using them — and `tailscale serve --https=<port>` only accepts **443, 8443, 10000**. Custom ports cannot use the Tailscale-managed cert directly.
- Hermes's uvicorn serves plain HTTP only; it does not terminate TLS.

For this workflow the recommendation is plain HTTP over Tailscale: the WireGuard tunnel already encrypts everything end-to-end between laptop and VPS. Browsers will mark the page "Not secure" and block a few APIs that require secure contexts (clipboard, Service Workers, WebAuthn, etc.), which is usually acceptable for internal dashboards.

If a specific app needs HTTPS with the custom port, the cleanest path is a local reverse proxy (Caddy or nginx) on the VPS that terminates TLS using a cert obtained via `tailscale cert <host>.<tailnet>.ts.net`, with `reverse_proxy 127.0.0.1:<PORT>` behind it. See `references/https-with-caddy.md` if the user asks.

## Troubleshooting playbook

Use this as the diagnostic loop when a user reports the dashboard is unreachable.

1. **`ERR_CONNECTION_REFUSED` / "refused to connect"** on the `*.ts.net` URL
   - On the VPS: `ss -tlnp | grep :<PORT>`.
   - If it shows `127.0.0.1:<PORT>` → dashboard is loopback-only. Fix the bind address (this skill's Step 1).
   - If nothing listens → the process died. Read the unit log.
2. **Dashboard exits immediately after launch, log says "Web UI frontend not built and npm is not available."**
   - `npm`/`node` are missing from the process's PATH. Confirm with `bash -lc 'which npm'` — if that works, the issue is the PATH propagation. Use the launcher script from Step 1 which hard-codes `~/.local/bin`.
3. **`systemd-run --user` says "Failed to connect to bus"**
   - `export XDG_RUNTIME_DIR=/run/user/$(id -u)` before the command, or enable linger: `sudo loginctl enable-linger $USER`.
4. **Laptop resolves the hostname but the TCP connection hangs**
   - Likely a peer reachability / DERP issue. On the VPS run `tailscale ping <laptop-hostname>` and on the laptop run `tailscale ping <vps-hostname>` to confirm peering. Check `tailscale status` for derp relays.
5. **Works over Tailscale but the user wants to remove a stale public UDP rule (e.g., `UDP 9119`)**
   - Safe to delete; it serves no purpose and is confusing documentation for the future.
6. **SSH session exits 255 when running `nohup ... &` or `setsid ... &`**
   - Don't try to daemonize through SSH. Use `systemd-run --user` as in Step 2 — the session can return cleanly because the service is no longer attached to the pty.
   - **Also seen with a compound remote command** (`ssh host 'write script; pkill; systemd-run; status'`). SSH returns 255 after an early step and the rest is dropped — `systemd-run` never executes and `systemctl --user status` later reports "Unit hermes-dashboard.service could not be found." Fix: run `systemd-run` in its own SSH call, with no preceding `pkill`/`echo` chained in. Verify state in a separate call.
7. **Two processes listening on the same port number but different addresses (e.g., `127.0.0.1:9119` and `100.x.y.z:9119`)**
   - This is legal because bind addresses differ. It usually means an interactive-shell instance is still running alongside the systemd-user one. Kill the stray PID or exit the interactive shell.
8. **User asks "why can't I use https://..."**
   - See the "About HTTPS" section; summarize the port constraint (only 443/8443/10000 for `tailscale serve --https`) and point out that the tunnel is already encrypted.

## Canonical URLs after setup

Given a tailnet like `<TAILNET_NAME>.ts.net` and a host `hermes-<VPS_USER>`:

- `http://<TAILSCALE_DOMAIN>.ts.net:9119/` — Hermes Dashboard
- `http://<TAILSCALE_DOMAIN>.ts.net:9200/` — Gaming Dashboard (once deployed the same way)
- `http://<TAILSCALE_DOMAIN>.ts.net:<PORT>/` — any future dashboard following this pattern

## Extended notes

- `references/findings.md` — the full root-cause walkthrough and evidence from the first time this was diagnosed. Read it when the user wants to understand *why* each step exists, or when reproducing the diagnostic process on a new box that is misbehaving in new ways.
- `references/https-with-caddy.md` — sample Caddy configuration for terminating TLS per port using `tailscale cert`. Read only if the user explicitly wants HTTPS on custom ports.
