---
name: tailscale-remote-skill
description: 通过 Tailscale 组网从服务器远程操作本机桌面（macOS/Linux/Windows）：浏览器打开网页看效果、双向传文件、远程执行命令。适用于"把生成的 HTML 展示到用户浏览器""传文件到本机""在本机执行命令"等场景。需要服务器与本机已通过 Tailscale 组网，且服务器配置了到本机的 SSH 免密登录。
---

# Tailscale Remote Skill

通过 Tailscale 组网，从服务器远程操作本机桌面——打开浏览器看效果、传文件、执行命令。

## 快速开始（30 秒跑通，推荐）

```bash
# ① 首次：自动探测 IP 与 SSH 用户名，结果写入 ~/.tailscale-remote.env
bash ~/.pi/agent/skills/tailscale-remote-skill/scripts/probe.sh
source ~/.tailscale-remote.env      # ② 每次会话先加载配置

# ③ 起静态服务并打开本机浏览器（用法一，见下）
```

已配置过（存在 `~/.tailscale-remote.env`）时，probe.sh 会直接复用，**不要重复排查**。

## 前置条件（一次性配置）

1. **Tailscale 组网**：服务器与本机（macOS/Linux/Windows）都安装并登录 Tailscale，两台机器互相 ping 通。
   - 查看状态：`tailscale status`
   - 组网后两台机器有内网 IP（100.x.y.z 网段），互访无需公网、无需 SSH 隧道。
2. **SSH 免密**：服务器生成密钥（`ssh-keygen -t ed25519`），把公钥加入本机 `~/.ssh/authorized_keys`，并确认本机开启了远程登录（macOS：系统设置 → 通用 → 共享 → 远程登录）。
   - ⚠️ **SSH 用户名 = 本机操作系统登录名**（macOS 的账户名）。**不是** `tailscale status` 的 User 列——那一列是 Tailscale 账户 email 前缀（登录邮箱），用它当 SSH 用户名必然 Permission denied。不确定就交给 probe.sh 探测。
3. **配置持久化**（probe.sh 自动生成，也可手写）：

```bash
# ~/.tailscale-remote.env（probe.sh 生成；或手动创建）
export MAC_HOST="user@100.x.y.z"        # 本机：SSH 用户名@Tailscale IP
export MAC_TAILSCALE_IP="100.x.y.z"     # 本机 Tailscale IP
export SERVER_TAILSCALE_IP="100.x.y.z"  # 服务器 Tailscale IP（只监听该接口，不暴露公网）
```

## 安全准则（重要）

- **服务只监听服务器 Tailscale 接口**（`SERVER_TAILSCALE_IP`），绝不监听 `0.0.0.0` —— 否则暴露公网。
- 用完的服务记录 PID 并及时清理（见「服务管理」）；临时文件放 `/tmp/`。
- 在本机执行命令前，想清楚权限与副作用（`open` 无害，`rm` 要谨慎）。
- `tailscale status` 会显示 Tailscale 账户 email 前缀，属 tailnet 内部信息；不要在对话/文档中复述。

## 通用 SSH 参数

所有 ssh/scp 命令统一带（避免 host key 与超时问题）：

```bash
SSH_OPTS="-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5"
# ssh $SSH_OPTS "$MAC_HOST" '...'
# scp $SSH_OPTS ...
```

## 用法一：在本机浏览器打开网页看效果（最常用）

三步：起静态服务（绑定 Tailscale 接口，自动避开占用端口）→ curl 自检 → 远程 `open`。

```bash
PORT=8890
while ss -tln 2>/dev/null | grep -q ":$PORT "; do PORT=$((PORT + 1)); done   # 自动避让占用端口
HTML_DIR=/path/to/html/dir                       # 要展示的 HTML 所在目录
PAGE=index.html                                  # 入口页面
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
echo "$SERVE_PID" > /tmp/tailscale-remote-serve.pid   # 持久化 PID，便于清理
echo "serve PID: $SERVE_PID · http://${SERVER_TAILSCALE_IP}:${PORT}/${PAGE}"
sleep 1

# 服务器端自检（非 200 先修这里，别急着开浏览器）
curl -s -o /dev/null -w "%{http_code}" "http://${SERVER_TAILSCALE_IP}:${PORT}/${PAGE}"

# 本机浏览器打开
ssh $SSH_OPTS "$MAC_HOST" "open 'http://${SERVER_TAILSCALE_IP}:${PORT}/${PAGE}'"
```

### 服务管理

```bash
cat /tmp/tailscale-remote-serve.pid | xargs -r kill      # 停止上次的服务
ls /tmp/tailscale-remote-serve.log                       # 服务日志
```

**变体：直接打开本机上已有的本地文件**
```bash
ssh $SSH_OPTS "$MAC_HOST" "open ~/Downloads/xxx.html"
```

## 用法二：双向传文件

```bash
# 服务器 → 本机（默认传到家目录）
scp $SSH_OPTS /path/on/server/file.html "$MAC_HOST":~/Downloads/

# 本机 → 服务器
scp $SSH_OPTS "$MAC_HOST":~/Downloads/xxx.png /tmp/

# 整目录（递归）
scp -r $SSH_OPTS /path/on/server/dir "$MAC_HOST":~/Downloads/
```

## 用法三：远程执行本机命令

```bash
# 任意命令
ssh $SSH_OPTS "$MAC_HOST" 'echo hi; uname -a'

# 看本机是否有文件
ssh $SSH_OPTS "$MAC_HOST" 'ls ~/Downloads/ | head'

# 打开应用/访达
ssh $SSH_OPTS "$MAC_HOST" 'open -a "Finder" ~/Downloads'
```

## 排障（按顺序查，命中即止）

| 症状 | 检查 |
|---|---|
| SSH 失败（Permission denied） | ① `tailscale status` 确认本机在线；② **用户名**：先 `source ~/.tailscale-remote.env`，或 `ssh -o BatchMode=yes <Mac登录名>@<IP> 'echo ok'` —— 别用 tailscale status 的 User 列（那是 email 前缀）；③ 公钥：`cat ~/.ssh/id_*.pub` 确认已加入本机 `~/.ssh/authorized_keys` |
| Host key verification failed | ssh 命令带 `-o StrictHostKeyChecking=accept-new`（首次自动记录） |
| 端口冲突 | 起服务时用 `while ss -tln ...` 自动避让；或 `ss -tlnp \| grep :PORT` 手动查 |
| 浏览器没弹出 | 确认本机 `open` 命令可用（`which open`）；改用 `open -a Safari <url>` |
| 本机离线 | `tailscale status` 看本机状态；让用户在桌面端重连 Tailscale |
| Windows/Linux 桌面 | 本机不是 macOS 时，把 `open` 换成 `xdg-open`（Linux）或 `start`（Windows cmd） |
