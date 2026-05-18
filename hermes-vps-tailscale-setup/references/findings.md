# Findings — First diagnosis of `hermes-<VPS_USER>` unreachability

This is the annotated debug log from the first time this problem was solved, preserved so the reasoning is reproducible. When a new Hermes VPS misbehaves in an unfamiliar way, use this as a template for how to investigate.

## Reported symptom

- Laptop is `<MACBOOK_HOSTNAME>` (Tailscale IP `<TAILSCALE_IP>`).
- VPS is `hermes-<VPS_USER>` (Tailscale IP `<TAILSCALE_IP>`), tailnet `<TAILNET_NAME>.ts.net`.
- Browser on the laptop opens `http://<TAILSCALE_DOMAIN>.ts.net:9119` → `This site can't be reached — refused to connect — ERR_CONNECTION_REFUSED`.
- User claims: Tailscale is up on both ends, Hermes dashboard is "enabled" at `http://127.0.0.1:9119`, cloud firewall has rules for UDP 41641, UDP 9119, TCP 1404, MagicDNS + HTTPS certs are on.

## Step 1 — verify what's claimed

Over SSH (`<USER>@<VPS_DOMAIN>.io:1404`):

```text path=null start=null
tailscale status
  <TAILSCALE_IP>  hermes-<VPS_USER>       <TAILSCALE_DOMAIN>.ts.net  linux
  <TAILSCALE_IP>  <MACBOOK_HOSTNAME>  <USER_EMAIL>@                  macOS  idle, tx 8320 rx 9456

tailscale ip -4
  <TAILSCALE_IP>

ss -tlnp | grep 9119
  LISTEN 0 2048  127.0.0.1:9119  users:(("hermes",pid=17897,fd=14))

tailscale serve status
  No serve config
```

Key findings:

- Tailscale is genuinely peered (non-zero rx/tx with the laptop).
- The dashboard is **only** on `127.0.0.1:9119`. This is the root cause of connection-refused: no socket exists at `<TAILSCALE_IP>:9119`, so the kernel returns TCP RST the moment SYN arrives on `tailscale0`.
- No `tailscale serve` config. Nothing is terminating HTTPS on the hostname either.
- `ufw` is not installed; "firewall" in this context is the cloud-provider firewall, not on-host.

## Step 2 — understand why the default is 127.0.0.1

`hermes dashboard --help` shows:

```text path=null start=null
--port PORT   (default 9119)
--host HOST   (default 127.0.0.1)
--insecure    Allow binding to non-localhost (DANGEROUS: exposes API keys on the network)
```

The default is loopback because the dashboard surfaces API keys; the maintainers gate non-loopback binds behind `--insecure`. The warning is accurate in general but less scary on a Tailscale-only bind, because only tailnet peers can reach the socket.

## Step 3 — first attempted fix (tailscale serve) and why we reverted it

Tried:

```bash path=null start=null
sudo tailscale serve --bg --https=443 http://127.0.0.1:9119
```

This works and yields `https://<TAILSCALE_DOMAIN>.ts.net/`, but the user requires per-port URLs (`…:9119`, `…:9200`, …) for consistency with future dashboards. `tailscale serve --https=<port>` only accepts 443, 8443, and 10000, so this approach is incompatible with the user's scheme. Rolled back:

```bash path=null start=null
sudo tailscale serve --https=443 off
```

## Step 4 — second attempted fix (bind to 0.0.0.0) and why we refined it

Binding to `0.0.0.0:9119` would have worked, but Hermes dashboards hold API keys and the cloud firewall rules are hand-edited; any future mistake opening TCP 9119 at the provider would leak credentials to the internet. Safer: bind specifically to the Tailscale IPv4. That IP is not attached to `eth0`, so even a permissive cloud firewall can't reach the socket.

Command attempted:

```bash path=null start=null
nohup hermes dashboard --host "$(tailscale ip -4 | head -1)" --port 9119 --insecure --no-open >log 2>&1 &
```

Immediately exited. Log:

```text path=null start=null
Web UI frontend not built and npm is not available.
Install Node.js, then run:  cd web && npm install && npm run build
```

## Step 5 — diagnosing the npm PATH issue

`which npm` in the non-interactive SSH shell returned nothing, but `bash -lc 'which npm'` returned `/home/<VPS_USER>/.local/bin/npm` (node v22.22.2, npm 10.9.7). `~/.local/bin` is prepended to PATH in `.bashrc`/`.profile`, and interactive login shells pick it up. The `nohup` command inherited the bare SSH environment.

Looking at `cli_main.py`:

```python path=null start=null
def cmd_dashboard(args):
    ...
    if not _build_web_ui(PROJECT_ROOT / "web", fatal=True):
        sys.exit(1)
    ...

def _build_web_ui(web_dir, *, fatal=False):
    if not (web_dir / "package.json").exists():
        return True
    npm = shutil.which("npm")
    if not npm:
        if fatal:
            print("Web UI frontend not built and npm is not available.")
            print("Install Node.js, then run:  cd web && npm install && npm run build")
        return not fatal
```

So: when `web/package.json` exists (it does) AND `npm` is not in PATH AND `fatal=True` (always for the dashboard command), the process exits 1. Solution: explicitly set PATH before launching.

## Step 6 — why SSH backgrounding failed (exit 255)

Attempting `ssh … 'setsid nohup …'` or similar from the caller's shell consistently returned exit 255 and the log file was never touched. This is a known class of issue: sshd waits on stdio of child processes even across `nohup`/`disown` if any descriptor is still tied to the pty. Under sshpass this gets tighter.

The clean workaround: fully detach the process from the SSH session using the already-running user systemd instance.

```bash path=null start=null
systemd-run --user --unit=hermes-dashboard --same-dir \
  --setenv=PATH=$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  "$HOME/start-hermes-dashboard.sh"
```

This worked immediately. `<VPS_USER>` had `Linger=yes` so the unit persists across SSH disconnect. After ~60 s (first-time `npm install && npm run build`), the dashboard listened on `<TAILSCALE_IP>:9119` and local `curl` returned 200.

## Step 7 — verification from the laptop

```text path=null start=null
dig +short <TAILSCALE_DOMAIN>.ts.net
  <TAILSCALE_IP>

curl -I http://<TAILSCALE_DOMAIN>.ts.net:9119/
  HTTP/1.1 405 Method Not Allowed
  server: uvicorn

curl http://<TAILSCALE_DOMAIN>.ts.net:9119/ | grep title
  <title>Hermes Agent</title>
```

`405` on `HEAD` is uvicorn's default (the Hermes route only declares `GET`). HTTP `200` on `GET` confirmed the UI loads.

## Residual observations worth remembering

- A second `hermes dashboard` process (no args) was left running on `127.0.0.1:9119` by an interactive shell. Because bind addresses differ, both sockets coexist legally on port 9119. It's harmless but noise — kill it by exiting the interactive shell or `kill <pid>`.
- `Invalid HTTP request received.` warnings in the dashboard log correspond to HTTPS clients probing an HTTP-only endpoint (e.g., user trying `https://…:9119`). Expected, ignorable.
- The cloud firewall had a stray `UDP 9119` rule. HTTP is TCP; the rule has no effect. Recommend deleting to avoid future confusion.

## Lessons carried into the skill

1. Start every diagnosis with `ss -tlnp | grep :<PORT>` to see the literal bind address. Do not trust `http://127.0.0.1:<PORT>` claims from documentation — verify the socket.
2. Prefer binding to the Tailscale IP (not `0.0.0.0`) for services that carry secrets. The public NIC then cannot host the socket even by accident.
3. For any interactive-shell-only PATH dependency, encode the PATH into a launcher script; do not rely on the shell inherited by `systemd-run` or `ssh`.
4. Use `systemd-run --user` (with lingering) as the default way to daemonize user-owned processes on modern Linux; it sidesteps SSH backgrounding hazards entirely.

## Second install — `<VPS_HOSTNAME>`, 90 s end-to-end

Applied the skill to `<USER>@<VPS_DOMAIN>.io` (host `<VPS_HOSTNAME>`, Tailscale IP `<TAILSCALE_IP>`). Prerequisites all passed on first check: `node`/`npm` already in `~/.local/bin`, `Linger=yes`, `~/.hermes/hermes-agent` present, another user systemd unit (`hermes-gateway.service`) already precedent-setting for this pattern.

What went wrong the first attempt:

- Built one large compound SSH invocation: write launcher → `chmod +x` → `pkill -f 'hermes dashboard'` → `systemd-run --user ...` → `systemctl --user status`. The remote shell returned exit 255 after the script-write and `pkill` steps, and everything after was silently skipped. Verification later showed `Unit hermes-dashboard.service could not be found.`
- Retried with a minimal, dedicated SSH call: just `systemd-run --user --unit=hermes-dashboard ... /home/zen/start-hermes-dashboard.sh`. Returned `Running as unit: hermes-dashboard.service; invocation ID: ...` immediately. After the usual ~60 s for first-time `npm install && npm run build`, the listener came up on `<TAILSCALE_IP>:9119`, local curl returned 200, and so did curl from the laptop against `<TAILSCALE_DOMAIN>.ts.net:9119`.

Additional friction observed:

- `pkill -f "hermes dashboard"` was pointless on a fresh box (nothing matched) and `pkill` returning non-zero exit can interact badly with chained remote shells under sshpass. Only use `pkill` when Step 3 actually shows a stray listener.
- Nested `$HOME` across client shell + sshpass + remote shell survived here, but it's a fragile dependency. Hard-code `/home/<user>/...` in the `systemd-run` line.

Lessons added to the skill:

- Keep the `systemd-run` SSH call to exactly one command.
- Skip `pkill` on first install.
- Use absolute paths in the `systemd-run` line.

## Third install — `<VPS_HOSTNAME>`, clean first-try

Applied the refined skill to `<USER>@<VPS_DOMAIN>.io` (host `<VPS_HOSTNAME>`, Tailscale IP `<TAILSCALE_IP>`). Followed the exact Step 1–3 sequence from the updated `SKILL.md`:

1. One prereq SSH call — all green: `node`/`npm` in login PATH, `Linger=yes`, `~/.hermes/hermes-agent` present, `hermes-gateway.service` precedent, no stray listener on 9119.
2. One SSH call to base64-decode the launcher into `/home/tai/start-hermes-dashboard.sh` and `chmod +x`.
3. One dedicated SSH call running just `systemd-run --user --unit=hermes-dashboard --same-dir --setenv=PATH=... /home/tai/start-hermes-dashboard.sh`. Returned `Running as unit: hermes-dashboard.service; invocation ID: ...` immediately.

Verification after ~70 s: socket on `<TAILSCALE_IP>:9119`, local curl = 200, laptop curl to `http://<TAILSCALE_DOMAIN>.ts.net:9119/` = 200 with `<title>Hermes Agent</title>`.

No retries, no exit-255 symptoms, no new lessons to capture. The refinements from the `<VPS_HOSTNAME>` install (dedicated `systemd-run` call, absolute paths, skip `pkill`) held up cleanly, so the procedure is now considered stable across three hosts on this tailnet: `hermes-<VPS_USER>`, `<VPS_HOSTNAME>`, `<VPS_HOSTNAME>`.

With those refinements the whole second setup took one prereq call + one launch call + one verify call — roughly 90 s including the initial `npm install && npm run build`.
5. Understand the Tailscale serve HTTPS port restriction (443/8443/10000) before promising HTTPS on a custom port to the user.
