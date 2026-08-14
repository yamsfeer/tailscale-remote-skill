# 变更记录（v1 → v2 → v3）

> 记录旧版的实际缺陷、修复方式与设计取舍，方便维护者理解每一次改动的动机。

## v2 → v3（服务生命周期 + 配置收敛 + Skill 瘦身）

### 动机

1. **服务残留无解**：v2 的 PID 持久化依赖“记得清理”，Agent 会话关闭后服务无限残留（实测抓到挂了两周的残留进程）
2. **隐私存放粗放**：配置 `~/.tailscale-remote.env` 权限 644、probe.sh 明文回显 IP/用户名
3. **给 Agent 用成本高**：SKILL.md 每次全量读 6.7KB 含 100 行 shell；起服务要手工写 30 行 node

### 改动

| 改动 | 说明 |
|---|---|
| 配置收敛到 skill 目录 | `tailscale-remote.env` 与 SKILL.md 同级；权限 600；probe.sh 回显打码；旧配置自动迁移；.gitignore 忽略 |
| 端口生命周期三层机制 | 滑动过期 TTL + 启动先杀旧 + cleanup.sh 一键清理（详见 ARCHITECTURE.md「服务生命周期」） |
| serve.sh / cleanup.sh | 起服务一行命令（避端口 / 自检 / PID / 滑动过期 / --open）；手动清理一条命令 |
| SKILL.md 瘦身 -45% | 命令模板外置 docs/COMMANDS.md，按需读取 |

### 修掉的 bug

| 缺陷 | 根因与修复 |
|---|---|
| `--ttl 0.03` 参数错乱 | bash `for arg in "$@"` 的迭代列表在循环前展开，循环内 shift 无效；改 while 循环 |
| 服务正常自检却 502 | 环境 http_proxy 未排除 Tailscale IP；自检 curl 加 `--noproxy '*'` |

### 设计取舍

1. 滑动过期 > 固定定时器：用户正看时不被掐断，“有人用就一直活，没人用自动死”
2. 单实例语义：展示场景一次一个页面，永远只有最新服务，PID / 清理逻辑简化
3. 不用 systemd / launchd / timer：skill 场景不引入新依赖（macOS 无默认 timeout）

### 验证方式

```bash
bash <skill目录>/scripts/serve.sh /tmp/xxx index.html        # 起服务 + 自检 200
bash <skill目录>/scripts/serve.sh /tmp/xxx index.html        # 再次运行：先杀旧再起新
bash <skill目录>/scripts/serve.sh /tmp/xxx index.html --ttl 0.03   # 3 秒后应自动退出
ls /tmp/tailscale-remote-serve.pid                            # 应已随退出清理
bash <skill目录>/scripts/cleanup.sh                           # 一键停止
```

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
# 首次（模拟全新环境；v2 时期配置在 ~/.tailscale-remote.env，v3 起在 skill 目录）
rm -f <skill目录>/tailscale-remote.env
bash scripts/probe.sh        # 应自动探测 IP 与用户名并写入 env
source ~/.tailscale-remote.env
ssh -o BatchMode=yes "$MAC_HOST" 'echo ok'   # 应一把通

# 二次运行
bash scripts/probe.sh        # 应直接复用已有配置，不再探测
```
