# Tailscale Remote Skill

通过 **Tailscale 组网**，从服务器远程操作本机桌面的通用 Agent Skill——**在浏览器打开网页看效果、双向传文件、远程执行命令**。

## 功能

| 能力 | 示例 |
|---|---|
| 本机浏览器打开网页 | Agent 在服务器生成 HTML → 用户立刻在本机浏览器看到效果 |
| 双向传文件 | `scp` 服务器 ↔ 本机 `~/Downloads/` |
| 远程执行命令 | `ssh` 查文件、开应用、执行任意命令 |

## 安装

```bash
# 复制到你的 agent skills 目录（按你的 agent 选择）
mkdir -p ~/.agents/skills/tailscale-remote
cp SKILL.md ~/.agents/skills/tailscale-remote/SKILL.md
# 软链给其他 agent（Claude Code / Pi 等）
ln -s ~/.agents/skills/tailscale-remote ~/.claude/skills/tailscale-remote
ln -s ~/.agents/skills/tailscale-remote ~/.pi/agent/skills/tailscale-remote
```

## 前置条件（一次性配置）

1. **Tailscale 组网**：服务器与本机都安装并登录 Tailscale，`tailscale status` 两台机器都在线（组网内互访无需公网、无需 SSH 隧道）
2. **SSH 免密登录**：服务器生成密钥（`ssh-keygen -t ed25519`），公钥加入本机 `~/.ssh/authorized_keys`，本机开启远程登录（macOS：系统设置 → 通用 → 共享 → 远程登录）
3. **配置两个环境变量**（或按 SKILL.md 中的占位符替换）：

```bash
export MAC_HOST="user@100.x.y.z"        # 本机：用户名@Tailscale IP
export SERVER_TAILSCALE_IP="100.x.y.z"  # 服务器 Tailscale IP
```

## 用法

完整命令（静态服务 + 浏览器打开 / scp 双向传文件 / ssh 远程命令）、安全准则（服务只监听 Tailscale 接口，绝不监听 `0.0.0.0`）与排障，见 [`SKILL.md`](SKILL.md)。

## License

Apache-2.0
