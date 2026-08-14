# Tailscale Remote Skill

通过 **Tailscale 组网**，从服务器远程操作本机桌面的通用 Agent Skill——**在浏览器打开网页看效果、双向传文件、远程执行命令**。

> 一句话原理：**Tailscale 只负责网络通达（IP 包可达），互相操作靠 SSH**。分层模型与各层职责见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

## 功能

| 能力 | 示例 |
|---|---|
| 本机浏览器打开网页 | Agent 在服务器生成 HTML → 用户立刻在本机浏览器看到效果 |
| 双向传文件 | `scp` 服务器 ↔ 本机 `~/Downloads/` |
| 远程执行命令 | `ssh` 查文件、开应用、执行任意命令 |

## 安装

```bash
# 复制到你的 agent skills 目录（按你的 agent 选择）
mkdir -p ~/.agents/skills/tailscale-remote-skill
cp SKILL.md ~/.agents/skills/tailscale-remote-skill/SKILL.md
cp -r scripts ~/.agents/skills/tailscale-remote-skill/scripts
# 软链给其他 agent（Claude Code / Pi 等）
ln -s ~/.agents/skills/tailscale-remote-skill ~/.claude/skills/tailscale-remote-skill
ln -s ~/.agents/skills/tailscale-remote-skill ~/.pi/agent/skills/tailscale-remote-skill
```

## 快速开始（30 秒跑通）

```bash
# ① 首次：自动探测 IP 与 SSH 用户名，结果写入 skill 目录（<skill目录>/tailscale-remote.env）
bash ~/.agents/skills/tailscale-remote-skill/scripts/probe.sh
source ~/.agents/skills/tailscale-remote-skill/tailscale-remote.env   # ② 每次会话先加载配置
# ③ 起静态服务并打开本机浏览器（完整命令见 SKILL.md「用法一」）
```

> **skill 目录** = SKILL.md 所在目录。配置随 skill 同目录存放（不散落 home），复制/迁移 skill 时配置跟着走。
已配置过（存在 `<skill目录>/tailscale-remote.env`）时 probe.sh 直接复用，无需重复排查。

## 前置条件（一次性配置）

1. **Tailscale 组网**：服务器与本机都安装并登录 Tailscale，`tailscale status` 两台机器都在线（组网内互访无需公网、无需 SSH 隧道）
2. **SSH 免密登录**：服务器生成密钥（`ssh-keygen -t ed25519`），公钥加入本机 `~/.ssh/authorized_keys`，本机开启远程登录（macOS：系统设置 → 通用 → 共享 → 远程登录）
   - ⚠️ SSH 用户名 = 本机操作系统登录名，**不是** `tailscale status` 的 User 列（那是账户 email 前缀）
3. **配置持久化**（probe.sh 自动生成，也可手写；位置 = skill 目录，与 SKILL.md 同级）：

```bash
# <skill目录>/tailscale-remote.env
# 配置文件含 IP 与用户名（权限 600），已加入仓库 .gitignore，切勿提交进 git
export MAC_HOST="user@100.x.y.z"        # 本机：SSH 用户名@Tailscale IP
export MAC_TAILSCALE_IP="100.x.y.z"     # 本机 Tailscale IP
export SERVER_TAILSCALE_IP="100.x.y.z"  # 服务器 Tailscale IP（只监听该接口，不暴露公网）
```

## 用法

完整命令（静态服务 + 浏览器打开 / scp 双向传文件 / ssh 远程命令）、安全准则（服务只监听 Tailscale 接口，绝不监听 `0.0.0.0`）与排障，见 [`SKILL.md`](SKILL.md)。

## 文档

| 文档 | 内容 |
|---|---|
| [SKILL.md](SKILL.md) | 使用手册：快速开始 / 用法 / 安全准则 / 排障 |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | 分层模型：Tailscale（网络层）vs SSH（操作层），各层职责与替代方案 |
| [docs/CHANGELOG.md](docs/CHANGELOG.md) | v1 → v2 缺陷记录、修复方式与设计取舍 |

## License

Apache-2.0
