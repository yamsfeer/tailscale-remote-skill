---
name: tailscale-remote
description: >-
  Remotely operate a desktop machine (macOS/Linux/Windows) from a server over
  a Tailscale mesh: open pages in the user's browser, transfer files both ways,
  and run remote commands. Use when the user wants to "see generated HTML in
  the browser", "send files to/from the local machine", or "run a command
  locally". Requires Tailscale mesh between server and desktop, plus
  passwordless SSH from server to desktop. / 通过 Tailscale 组网从服务器远程
  操作本机桌面：浏览器打开网页看效果、双向传文件、远程执行命令。
---

# Tailscale Remote Skill

Operate a desktop machine from a server over a Tailscale mesh — open pages in
the user's browser, transfer files, run remote commands.

## Prerequisites (one-time setup)

1. **Tailscale mesh**: install and log in to Tailscale on both the server and
   the desktop (macOS/Linux/Windows). Verify with `tailscale status`; the two
   machines should ping each other. Mesh nodes get private 100.x.y.z
   addresses — direct access without public exposure or SSH tunneling.
2. **Passwordless SSH**: generate a key on the server (`ssh-keygen -t ed25519`),
   append the public key to the desktop's `~/.ssh/authorized_keys`, and enable
   remote login on the desktop (macOS: System Settings → General → Sharing →
   Remote Login).
3. **Configure environment variables** (or substitute the placeholders below):

```bash
# Recommended: add to your shell profile (~/.bashrc or ~/.zshrc)
export MAC_HOST="user@100.x.y.z"        # Desktop: user@Tailscale IP
export SERVER_TAILSCALE_IP="100.x.y.z"  # Server Tailscale IP (listen only on this)
```

## Security rules (important)

- **Listen only on the server's Tailscale interface** (`SERVER_TAILSCALE_IP`),
  never on `0.0.0.0` — that would expose the service to the public internet.
- Track the PID of any server you start and clean it up when done; put
  temporary files in `/tmp/`.
- Before running commands on the desktop, consider permissions and side
  effects (`open` is harmless; `rm` is not).

## Usage 1: Open a page in the desktop browser (most common)

Three steps: start a static server (bound to the Tailscale interface) →
self-check with curl → remote `open`.

```bash
PORT=8890                                        # pick a free port
HTML_DIR=/path/to/html/dir                       # directory containing the HTML
PAGE=index.html                                  # entry page
cat > /tmp/tailscale-remote-serve.mjs << EOF
import http from 'node:http';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
const PORT = ${PORT}, HOST = '${SERVER_TAILSCALE_IP}';
http.createServer((req, res) => {
  const url = new URL(req.url, 'http://x');
  const file = url.pathname === '/' ? '/${PAGE}' : url.pathname;
  try {
    const body = readFileSync(join('${HTML_DIR}', file));
    const ext = file.split('.').pop();
    const mime = { html: 'text/html; charset=utf-8', css: 'text/css', js: 'text/javascript', png: 'image/png', jpg: 'image/jpeg', svg: 'image/svg+xml' };
    res.writeHead(200, { 'content-type': (mime[ext] || 'application/octet-stream') });
    res.end(body);
  } catch { res.writeHead(404); res.end('404'); }
}).listen(PORT, HOST, () => console.log('serving http://' + HOST + ':' + PORT + '/'));
EOF
node /tmp/tailscale-remote-serve.mjs > /tmp/tailscale-remote-serve.log 2>&1 &
SERVE_PID=$!
echo "serve PID: $SERVE_PID"
sleep 1

# Self-check from the server
curl -s -o /dev/null -w "%{http_code}" "http://${SERVER_TAILSCALE_IP}:${PORT}/${PAGE}"

# Open in the desktop browser
ssh -o BatchMode=yes "$MAC_HOST" "open 'http://${SERVER_TAILSCALE_IP}:${PORT}/${PAGE}'"
```

The server stays in the background (PID in `$SERVE_PID`); `kill $SERVE_PID`
when the user is done.

**Variant: open a local file already on the desktop**
```bash
ssh -o BatchMode=yes "$MAC_HOST" "open ~/Downloads/xxx.html"
```

## Usage 2: Transfer files both ways

```bash
# Server → desktop (defaults to the home directory)
scp -o BatchMode=yes /path/on/server/file.html "$MAC_HOST":~/Downloads/

# Desktop → server
scp -o BatchMode=yes "$MAC_HOST":~/Downloads/xxx.png /tmp/

# Whole directory (recursive)
scp -r -o BatchMode=yes /path/on/server/dir "$MAC_HOST":~/Downloads/
```

## Usage 3: Run remote commands on the desktop

```bash
# Any command
ssh -o BatchMode=yes "$MAC_HOST" 'echo hi; uname -a'

# Check whether a file exists on the desktop
ssh -o BatchMode=yes "$MAC_HOST" 'ls ~/Downloads/ | head'

# Open an app or Finder
ssh -o BatchMode=yes "$MAC_HOST" 'open -a "Finder" ~/Downloads'
```

## Troubleshooting

| Symptom | Check |
|---|---|
| SSH fails (Permission denied) | `tailscale status` shows the desktop online? Public key in the desktop's `~/.ssh/authorized_keys`? `ssh -o BatchMode=yes "$MAC_HOST" 'echo ok'` |
| Port conflict | `ss -tlnp \| grep :PORT` to find the occupant, pick another port |
| Browser didn't open | Confirm `open` exists on the desktop (`which open`); fall back to `open -a Safari <url>` |
| Desktop offline | `tailscale status` — ask the user to reconnect Tailscale on the desktop |
| Windows/Linux desktop | Not macOS: replace `open` with `xdg-open` (Linux) or `start` (Windows cmd) |

## Install into your agent

```bash
# Copy to your agent's skills directory (choose per your agent)
mkdir -p ~/.agents/skills ~/.claude/skills ~/.pi/agent/skills
cp -r skills/tailscale-remote ~/.agents/skills/
# Symlink for other agents:
ln -s ~/.agents/skills/tailscale-remote ~/.claude/skills/tailscale-remote
ln -s ~/.agents/skills/tailscale-remote ~/.pi/agent/skills/tailscale-remote
```
