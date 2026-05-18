# 9Router on onemin-center — Setup & Configuration

9Router (v0.4.18) running on `onemin-center` VPS, accessible remotely via Tailscale from MacOS.

## Access URLs (from Mac via Tailscale)

- **Dashboard:** http://onemin-center:20128/dashboard
- **API endpoint:** http://onemin-center:20128/v1
- **Direct IP alternative:** http://<TAILSCALE_IP>:20128/dashboard

### Connect AI tools (Claude Code, Cursor, Cline, etc.)

```
Endpoint: http://onemin-center:20128/v1
API Key:  (copy from dashboard)
Model:    (select from dashboard)
```

## VPS Details

| Item | Value |
|------|-------|
| Host | `<VPS_DOMAIN>.io` |
| SSH port | `1404` |
| User | `ca` |
| OS | Ubuntu 24.04.4 LTS |
| Tailscale IP | `<TAILSCALE_IP>` |
| Tailscale hostname | `onemin-center` |
| Service port | `20128` |

### SSH access

```bash
ssh -p 1404 <USER>@<VPS_DOMAIN>.io
# or via Tailscale:
ssh -p 1404 ca@onemin-center
```

## Architecture

```
MacOS (<MACBOOK_HOSTNAME>)
  │
  │  WireGuard tunnel (encrypted end-to-end)
  │
  ▼
onemin-center (<TAILSCALE_IP>)
  │
  └─ 9router :20128
       ├─ /dashboard  → Web UI
       └─ /v1         → OpenAI-compatible API
```

All traffic is encrypted by Tailscale's WireGuard tunnel — HTTP is safe here.

## Installed Software

- **Node.js:** v22.22.2 (via nvm at `/home/ca/.nvm`)
- **npm:** 10.9.7
- **9router:** v0.4.18 (global npm package)

## Service Configuration

### Launcher script — `/home/ca/start-9router.sh`

```bash
#!/bin/bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

TS_IP=$(tailscale ip -4 | head -1)

export PORT=20128
export HOSTNAME="$TS_IP"
export NEXT_PUBLIC_BASE_URL="http://$TS_IP:20128"

exec 9router
```

### Systemd user service — `~/.config/systemd/user/9router.service`

```ini
[Unit]
Description=9Router AI Gateway
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/home/ca/start-9router.sh
Restart=always
RestartSec=5
Environment=XDG_RUNTIME_DIR=/run/user/1000

[Install]
WantedBy=default.target
```

### Persistence

- **Linger:** enabled (`loginctl enable-linger ca`) — service survives SSH disconnect and reboot
- **Auto-start:** enabled via `systemctl --user enable 9router`

## Service Management

SSH into VPS, then:

```bash
# Status
systemctl --user status 9router

# Restart
systemctl --user restart 9router

# Stop
systemctl --user stop 9router

# Live logs
journalctl --user -u 9router -f

# Last 50 log lines
journalctl --user -u 9router --no-pager -n 50
```

## Updating 9Router

```bash
# SSH into VPS
ssh -p 1404 <USER>@<VPS_DOMAIN>.io

# Load nvm
export NVM_DIR="$HOME/.nvm" && . "$NVM_DIR/nvm.sh"

# Update
npm update -g 9router

# Restart service
systemctl --user restart 9router
```

## Troubleshooting

### Service not running after reboot

```bash
export XDG_RUNTIME_DIR=/run/user/$(id -u)
systemctl --user status 9router
# If stopped:
systemctl --user start 9router
```

### Port not listening

```bash
ss -tlnp | grep 20128
# Should show: LISTEN 0.0.0.0:20128
```

### Can't reach from Mac

1. Check Tailscale is connected on both ends: `tailscale status`
2. Check VPS peering: `tailscale ping onemin-center`
3. Check service is running (see above)

### Node.js path issues

nvm is loaded by the launcher script. If `9router` command is not found:

```bash
export NVM_DIR="$HOME/.nvm" && . "$NVM_DIR/nvm.sh"
which 9router
# Expected: /home/ca/.nvm/versions/node/v22.22.2/bin/9router
```

## Security Notes

- 9router binds to `0.0.0.0:20128` (Next.js default behavior)
- **Do NOT** open port 20128 on the cloud provider firewall
- Only Tailscale UDP port (41641) and SSH port (1404) should be open on the public firewall
- WireGuard encrypts all traffic end-to-end between Mac and VPS

## Setup Date

2026-05-05
