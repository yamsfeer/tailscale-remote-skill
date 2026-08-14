---
name: tailscale-remote-skill
description: 通过 Tailscale 组网从服务器远程操作本机桌面（macOS/Linux/Windows）：浏览器打开网页看效果、双向传文件、远程执行命令。适用于"把生成的 HTML 展示到用户浏览器""传文件到本机""在本机执行命令"等场景。需要服务器与本机已通过 Tailscale 组网，且服务器配置了到本机的 SSH 免密登录。
---

# Tailscale Remote Skill

通过 Tailscale 组网，从服务器远程操作本机桌面——打开浏览器看效果、传文件、执行命令。

> **skill 目录** = 本 SKILL.md 所在目录（软链会自动解析到真实位置）。配置 `<skill目录>/tailscale-remote.env` 与 skill 同目录存放，不散落 home。

## 快速开始（30 秒跑通，推荐）

```bash
# ① 首次：自动探测 IP 与 SSH 用户名，结果写入 <skill目录>/tailscale-remote.env
bash ~/.pi/agent/skills/tailscale-remote-skill/scripts/probe.sh
source ~/.pi/agent/skills/tailscale-remote-skill/tailscale-remote.env   # ② 每次会话先加载配置

# ③ 起静态服务并在本机浏览器打开（用法一，见下）
```

已配置过（存在 `<skill目录>/tailscale-remote.env`）时，probe.sh 会直接复用，**不要重复排查**。

## 前置条件（一次性配置）

1. **Tailscale 组网**：服务器与本机（macOS/Linux/Windows）都安装并登录 Tailscale，两台机器互相 ping 通。
   - 查看状态：`tailscale status`
   - 组网后两台机器有内网 IP（100.x.y.z 网段），互访无需公网、无需 SSH 隧道。
2. **SSH 免密**：服务器生成密钥（`ssh-keygen -t ed25519`），把公钥加入本机 `~/.ssh/authorized_keys`，并确认本机开启了远程登录（macOS：系统设置 → 通用 → 共享 → 远程登录）。
   - ⚠️ **SSH 用户名 = 本机操作系统登录名**（macOS 的账户名）。**不是** `tailscale status` 的 User 列——那一列是 Tailscale 账户 email 前缀（登录邮箱），用它当 SSH 用户名必然 Permission denied。不确定就交给 probe.sh 探测。
3. **配置持久化**（probe.sh 自动生成，也可手写；位置 = skill 目录，即 SKILL.md 同级）：

```bash
# <skill目录>/tailscale-remote.env（probe.sh 生成；或手动创建）
export MAC_HOST="user@100.x.y.z"        # 本机：SSH 用户名@Tailscale IP
export MAC_TAILSCALE_IP="100.x.y.z"     # 本机 Tailscale IP
export SERVER_TAILSCALE_IP="100.x.y.z"  # 服务器 Tailscale IP（只监听该接口，不暴露公网）
```

## 安全准则（重要）

- **配置收敛在 skill 目录**：`<skill目录>/tailscale-remote.env`（probe.sh 自动写入，权限 600），不向 home 目录散落；**不要把它提交进 git**（仓库 .gitignore 已忽略，复制 skill 时注意）。
- **终端/日志不回显完整 IP**：probe.sh 探测过程打印的是打码地址；确需排查时再看配置文件本身。
- **服务只监听服务器 Tailscale 接口**（`SERVER_TAILSCALE_IP`），绝不监听 `0.0.0.0` —— 否则暴露公网。
- **服务不会无限残留**：serve.sh 起的服务无访问 15 分钟（可 `--ttl` 改）自动退出；单实例语义，再次 serve 会先杀掉旧服务；`cleanup.sh` 随时一键停止。
- 在本机执行命令前，想清楚权限与副作用（`open` 无害，`rm` 要谨慎）。
- `tailscale status` 会显示 Tailscale 账户 email 前缀，属 tailnet 内部信息；不要在对话/文档中复述。

## 核心用法

### 用法一：在本机浏览器打开网页看效果（最常用）

```bash
# 一行搞定：自动避端口 → 起服务 → 自检 → PID 持久化；--open 自动开本机浏览器
bash <skill目录>/scripts/serve.sh <html目录> [入口页] [--open] [--ttl 分钟]

# 示例
bash ~/.pi/agent/skills/tailscale-remote-skill/scripts/serve.sh /tmp/preview index.html --open
```

- 端口从 8890 起自动避让，URL 由脚本打印，**不用记端口**
- 无访问默认 15 分钟自动退出（滑动过期），不会无限残留
- 停止：`bash <skill目录>/scripts/cleanup.sh`（不用记端口/PID）

### 用法二：双向传文件

```bash
scp $SSH_OPTS /path/on/server/file.html "$MAC_HOST":~/Downloads/   # 服务器 → 本机
scp $SSH_OPTS "$MAC_HOST":~/Downloads/xxx.png /tmp/                 # 本机 → 服务器
```

### 用法三：远程执行本机命令

```bash
ssh $SSH_OPTS "$MAC_HOST" 'ls ~/Downloads/ | head'    # 查文件
ssh $SSH_OPTS "$MAC_HOST" 'open -a "Finder" ~/Downloads'   # 开应用/访达
```

> 完整手工模板（定制 node 服务、rsync、非 macOS 本机等）见 `<skill目录>/docs/COMMANDS.md`，按需读取。

## 排障（按顺序查，命中即止）

| 症状 | 检查 |
|---|---|
| SSH 失败（Permission denied） | ① `tailscale status` 确认本机在线；② **用户名**：先 `source <skill目录>/tailscale-remote.env`，或 `ssh -o BatchMode=yes <Mac登录名>@<IP> 'echo ok'` —— 别用 tailscale status 的 User 列（那是 email 前缀）；③ 公钥：`cat ~/.ssh/id_*.pub` 确认已加入本机 `~/.ssh/authorized_keys` |
| Host key verification failed | ssh 命令带 `-o StrictHostKeyChecking=accept-new`（首次自动记录） |
| 端口冲突 | serve.sh 已自动避让；手工版用 `ss -tlnp \| grep :PORT` 查 |
| 浏览器没弹出 | 确认本机 `open` 命令可用（`which open`）；改用 `open -a Safari <url>` |
| 本机离线 | `tailscale status` 看本机状态；让用户在桌面端重连 Tailscale |
| Windows/Linux 桌面 | 本机不是 macOS 时，把 `open` 换成 `xdg-open`（Linux）或 `start`（Windows cmd） |

## 文档索引

| 文档 | 内容 |
|---|---|
| docs/COMMANDS.md | 完整命令模板（手工版 serve / scp / rsync / ssh 变体） |
| docs/ARCHITECTURE.md | 分层模型：Tailscale（网络层）vs SSH（操作层） |
| docs/CHANGELOG.md | v1 → v2 缺陷记录与设计取舍 |
