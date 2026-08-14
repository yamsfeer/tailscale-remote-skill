# 变更记录（v1 → v2）

> 记录旧版的实际缺陷、修复方式与设计取舍，方便维护者理解每一次改动的动机。

## v1 的实际缺陷

v1 的**命令是对的**，问题出在**假设不成立**：它假设使用者已经知道 SSH 用户名、已经信任了 host key、端口不会冲突、环境变量已经配好。真实使用中每一条都会卡壳，且失败信息高度相似（都是 `Permission denied` / `Host key verification failed`），导致每次都要从头排查一遍。

| 缺陷 | 现象 | 根因 |
|---|---|---|
| 用户名来源不清 | `Permission denied`，反复尝试不同用户名 | 文档未说明「SSH 用户名 = 本机系统登录名」，`tailscale status` 的 User 列（账户 email 前缀）极具误导性 |
| host key 反复失败 | `Host key verification failed` | 命令模板没带 `StrictHostKeyChecking=accept-new`，首次连接被拒 |
| 每次从头排查 | 环境变量为空，每次手动指定 IP / 用户名 | 没有「上次已跑通配置」的持久化机制 |
| 端口撞车 | 静态服务起不来或指向旧服务 | 固定端口（8890），无占用检测 |
| 服务残留 | 旧服务占着端口 | 服务 PID 未持久化，没有清理手段 |
| 原理不明 | 使用者不知道各层职责，排障方向错 | 没有说明 Tailscale 只做网络层、SSH 做操作层的边界 |

## v2 的修复

| 修复 | 位置 | 说明 |
|---|---|---|
| `scripts/probe.sh` 自动探测 | 新增脚本 | 自动定位服务器/本机 Tailscale IP、逐候选探测可用 SSH 用户名（纯公钥认证，无爆破），把结果持久化到 `~/.tailscale-remote.env`；二次运行直接复用，不再重复排查 |
| 统一 SSH 参数 | SKILL.md | 所有 ssh/scp 命令带 `SSH_OPTS="-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5"` |
| 端口自动避让 | SKILL.md 用法一 | `while ss -tln | grep -q ":$PORT"` 自动换到空闲端口 |
| PID 持久化 + 服务管理 | SKILL.md 新增小节 | PID 写入 `/tmp/tailscale-remote-serve.pid`，一条命令清理残留服务 |
| 快速开始 | SKILL.md 开头 | 「30 秒跑通」三段式：探测 → source → 起服务，把最长路径前置 |
| 原理文档 | docs/ARCHITECTURE.md | 分层模型 + 各层职责 + 替代方案辨析 + 常见误区 |
| 本变更记录 | docs/CHANGELOG.md | 缺陷 → 修复 → 为什么 |

## 设计取舍

1. **配置与模板分离**：把每台机器都不同、容易记错的东西（IP、用户名）固化成配置文件（`~/.tailscale-remote.env`），把稳定不变的操作模板留在 SKILL.md。换机器只改配置，模板永不动。
2. **探测脚本只做公钥尝试，不做爆破**：候选用户名仅限本机当前用户 + 少量常见登录名，全部走 `BatchMode=yes`（不触发密码交互），失败即跳过，无安全风险。
3. **Tailscale SSH 定位为可选**：它替代「通道层 + 认证层」，但对 Agent 场景（需在本机 sudo 开启、macOS GUI 托管时命令行易失败、有 host key 与 ACL 配置成本）并不比「系统 SSH + 公钥」省事，故不进主流程。
4. **失败信息按层排查**：SSH 失败时 `Permission denied` 无法区分缺哪层，因此排障表按「用户名 → 公钥 → 通道 → 网络」顺序列出，命中即止，避免无效排查。

## 验证方式

```bash
# 首次（模拟全新环境）
rm -f ~/.tailscale-remote.env
bash scripts/probe.sh        # 应自动探测 IP 与用户名并写入 env
source ~/.tailscale-remote.env
ssh -o BatchMode=yes "$MAC_HOST" 'echo ok'   # 应一把通

# 二次运行
bash scripts/probe.sh        # 应直接复用已有配置，不再探测
```
