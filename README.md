# Tailscale Remote Skill

A generic Agent Skill: operate your desktop machine from a server over a
Tailscale mesh — **open pages in the browser to see results, transfer files
both ways, and run remote commands**.

通用的 Agent Skill：通过 Tailscale 组网，从服务器远程操作本机桌面——
**在浏览器打开网页看效果、双向传文件、远程执行命令**。

[中文说明](#安装-installation) · [English](#installation)

## What it does

| Capability | Example |
|---|---|
| Open a page in the desktop browser | Agent generates HTML on the server → user sees it in the local browser instantly |
| Transfer files both ways | `scp` between server and desktop `~/Downloads/` |
| Run remote commands | `ssh` to check files, open apps, run anything |

## Installation

```bash
# Copy the skill into your agent's skills directory
mkdir -p ~/.agents/skills
cp -r skills/tailscale-remote ~/.agents/skills/
# Symlink for other agents (Claude Code / Pi / etc.)
ln -s ~/.agents/skills/tailscale-remote ~/.claude/skills/tailscale-remote
ln -s ~/.agents/skills/tailscale-remote ~/.pi/agent/skills/tailscale-remote
```

## Prerequisites

1. **Tailscale mesh** between the server and your desktop (both installed and
   logged in; `tailscale status` shows both online).
2. **Passwordless SSH** from server to desktop (public key in
   `~/.ssh/authorized_keys`, remote login enabled).
3. Configure two environment variables:

```bash
export MAC_HOST="user@100.x.y.z"        # Desktop: user@Tailscale IP
export SERVER_TAILSCALE_IP="100.x.y.z"  # Server Tailscale IP
```

## Usage

See [`skills/tailscale-remote/SKILL.md`](skills/tailscale-remote/SKILL.md) for
the full command recipes (static server + browser open, scp both ways, ssh
remote commands), security rules (listen only on the Tailscale interface —
never `0.0.0.0`), and troubleshooting.

## 安装

```bash
# 复制到你的 agent skills 目录
mkdir -p ~/.agents/skills
cp -r skills/tailscale-remote ~/.agents/skills/
# 软链给其他 agent（Claude Code / Pi 等）
ln -s ~/.agents/skills/tailscale-remote ~/.claude/skills/tailscale-remote
ln -s ~/.agents/skills/tailscale-remote ~/.pi/agent/skills/tailscale-remote
```

## 前置条件

1. 服务器与本机安装并登录 **Tailscale**，`tailscale status` 两台机器都在线
2. 服务器到本机 **SSH 免密登录**（公钥加入 `~/.ssh/authorized_keys`，本机开启远程登录）
3. 配置两个环境变量：

```bash
export MAC_HOST="user@100.x.y.z"        # 本机：用户名@Tailscale IP
export SERVER_TAILSCALE_IP="100.x.y.z"  # 服务器 Tailscale IP
```

## 用法

完整命令（静态服务 + 浏览器打开 / scp 双向传文件 / ssh 远程命令）、安全准则
（服务只监听 Tailscale 接口，绝不监听 `0.0.0.0`）与排障，见
[`skills/tailscale-remote/SKILL.md`](skills/tailscale-remote/SKILL.md)。

## License

Apache-2.0
