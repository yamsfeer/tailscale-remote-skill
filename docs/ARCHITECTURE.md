# 架构与原理

> 为什么这个 Skill 是这么设计的——先讲清楚分层，再讲每个条件的职责边界。

## 一句话模型

> **Tailscale 只负责「网络通达」；「互相操作」要靠 SSH；SSH 能通需要四个条件同时满足。**

很多人误以为 Tailscale 通了就等于能操作对方机器。不是的。Tailscale 的职责边界非常窄：它只保证 **IP 层的网络包能到达对方**（100.x.y.z 网段互 ping 通）。包到达之后，对方机器上**有没有服务在听、认不认你的身份**，是另一回事——那是 SSH 的职责。

## 分层模型

```
┌─ 网络层 ────────────────  Tailscale
│                          IP 包可达（100.x.y.z 互 ping 通）
│
├─ 通道层 ────────────────  SSH 服务（sshd）
│                          macOS 上开它的开关叫「远程登录」
│                          （系统设置 → 通用 → 共享 → 远程登录）
│
├─ 认证层 ────────────────  公钥（推荐） / 密码
│                          免密 = 服务器公钥在本机 ~/.ssh/authorized_keys 里
│
└─ 参数层 ────────────────  用户名 + IP + host key 信任
                           用户名 = 本机操作系统登录名
```

四层都通 = 整体通。缺任何一层，`ssh` 都会失败，而且失败信息往往只告诉你「Permission denied」，不会告诉你缺的是哪层——这就是排障要按层查的原因。

## 各层详解

### 1. 网络层：Tailscale

- **职责**：只做 IP 可达。两端安装并登录同一个 tailnet 后，互相有 100.x.y.z 内网 IP，无需公网、无需端口映射。
- **不做的事**：不负责认证、不负责替你打开服务端口、不保证对方有服务在听。
- **验证**：`tailscale status` 看到两台机器在线。

### 2. 通道层：SSH 服务（sshd）

- **职责**：在对方机器上监听 22 端口、接受连接、执行命令。
- **关键认识**：macOS 上的「远程登录」开关**就是**打开 sshd 的开关。它不是 SSH 的「替代方案」，而是 SSH 方案的组成部分。在 macOS 上开启方式：
  - GUI：系统设置 → 通用 → 共享 → 远程登录 → 开
  - CLI：`sudo systemsetup -setremotelogin on`
- **注意**：macOS 新版由 launchd 按需拉起 sshd，`lsof` 看不到常驻监听属正常现象，SSH 能连上即证明通道是开的。
- **验证**：`ssh -o BatchMode=yes <用户>@<IP> 'echo ok'`

### 3. 认证层：公钥 vs 密码

| 方式 | 适用 | 为什么 |
|---|---|---|
| **公钥** | Agent 自动化（本 Skill 的目标场景） | 全程免交互，`BatchMode=yes` 一把通；配置一次永久生效 |
| 密码 | 人工偶尔使用 | 会卡在交互式输入，Agent 无法处理 |

公钥配置（一次性）：

```bash
# 服务器侧生成密钥（已有可跳过）
ssh-keygen -t ed25519

# 把服务器公钥加入本机（Mac）的 authorized_keys
# 在 Mac 上执行：
echo '<服务器 ~/.ssh/id_ed25519.pub 的内容>' >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

### 4. 参数层：用户名 + IP + host key

- **用户名 = 本机操作系统登录名**（macOS 的账户名）。
  ⚠️ **不要**用 `tailscale status` 的 User 列——那一列显示的是 **Tailscale 账户 email 前缀**（如 `xxx@`），不是 SSH 用户名，用它连接必然 Permission denied。这是本 Skill 踩过的最隐蔽的坑，已由 `scripts/probe.sh` 自动探测解决。
- **IP**：用 Tailscale 内网 IP（100.x.y.z）。
- **host key 信任**：首次连接需记录对方主机指纹，ssh 命令统一带 `-o StrictHostKeyChecking=accept-new` 自动完成。

## 服务生命周期（端口管理设计）

> 展示服务最终必须**自己退出**，且用户/Agent 无需记忆端口与 PID。

### 痛点

v2 的做法是把 PID 持久化到 `/tmp/tailscale-remote-serve.pid`、文档提醒“用完清理”——依赖**记得清理**。
Agent 场景下会话随时可能被关闭，服务无人清理就会无限残留（实测抓到过挂了两周的残留进程）。

### 设计目标

1. 无人值守也会自动结束（不依赖任何人记得清理）
2. 用户不需要记端口号、不需要记 PID
3. 不引入新依赖（macOS 没有默认 `timeout` 命令；不用 systemd / launchd）

### 三层机制

| 层 | 机制 | 解决什么 |
|---|---|---|
| 自动 | **滑动过期 TTL**（默认无访问 15 分钟自动退出，`--ttl` 可改） | 根本兜底：有人访问就续期，没人访问自己死 |
| 启动先杀旧 | serve.sh 每次先读 PID 文件，上次进程还活着就 kill | 单实例语义，不叠加残留 |
| 手动 | `scripts/cleanup.sh` 一键停止 | 想让服务立刻结束时，无需记忆端口/PID |

### 关键决策

- **滑动过期而非固定定时器**：固定定时器会在用户正看时掐断（体验差）；滑动过期保证“有人用就一直活，没人用 N 分钟自动死”。浏览器标签页持续访问 → 永不超时。
- **端口 8890 起自动避让**：URL 由 serve.sh 打印，用户无需记忆端口；端口号本身不是敏感信息，固定起始端口即可。
- **自动退出时清理 PID 文件**（node `unlinkSync`），避免死进程的 PID 文件残留；启动时 `kill -0` 校验，死 PID 直接清理。
- **curl 自检带 `--noproxy '*'`**：Tailscale IP 通常不在 no_proxy 列表，http_proxy 会让自检假失败（实测出现 502 假象）。
- **`--open` 平台检测在“本机”执行**：`uname -s` 是 SSH 到本机后运行（服务器是 Linux 不代表本机是 macOS），识别 open / xdg-open / start。
- **单实例取舍**：展示场景一次一个页面，单实例语义让“永远只有最新一个服务”，同时把 PID 文件、清理逻辑都简化为单文件。

## 替代方案辨析

| 方案 | 替代了哪层 | 代价 / 说明 |
|---|---|---|
| **密码认证** | 认证层 | 人工可用；Agent 场景不可用（交互卡住） |
| **Tailscale SSH** | 通道层 + 认证层 | 用 Tailscale 账户身份认证，不依赖系统「远程登录」与 authorized_keys；但需在本机 `sudo tailscale up --ssh`（macOS GUI 托管时命令行操作常失败，且会重置已有的 up 参数）；对 Agent 自动化并不比「SSH + 公钥」省事，属可选 |

## 为什么 Agent 场景推荐「SSH + 公钥」

1. **全自动**：`BatchMode=yes` 免交互，Agent 可无人值守执行。
2. **零额外服务**：只依赖 macOS 自带的 OpenSSH，不引入新组件。
3. **一次配置、永久生效**：配合 `scripts/probe.sh` 的配置持久化（`~/.tailscale-remote.env`），跑通一次就永远跑通。
4. **边界清晰**：网络层归 Tailscale、操作层归 SSH，哪层出问题按层排查即可。

## 常见误区

- ❌ 「Tailscale 通了就能操作对方」——它只保证 IP 通达。
- ❌ 「远程登录是可选的替代方案」——它是 SSH 方案的组成部分。
- ❌ 「tailscale status 的 User 列是 SSH 用户名」——那是账户 email 前缀。
- ❌ 「ssh 失败 = 网络不通」——先查通道层、认证层、参数层，再回头查网络层。
