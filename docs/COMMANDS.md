# 命令参考（完整模板）

> 本文件是 SKILL.md 的外置命令模板，**按需读取**。日常 90% 场景用 `scripts/serve.sh` 一行搞定，
> 需要手工/变体操作时再参考这里。所有变量来自 `<skill目录>/tailscale-remote.env`（先 source）。

## 通用 SSH 参数

所有 ssh/scp 命令统一带（避免 host key 与超时问题）：

```bash
SSH_OPTS="-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5"
```

## 用法一：起静态服务（手工完整版，通常直接用 serve.sh 即可）

```bash
# 一行版（推荐）：自动避端口 / 滑动过期 / PID 持久化 / 可选开浏览器
bash <skill目录>/scripts/serve.sh <html目录> [入口页] [--open] [--ttl 分钟]

# 手工版（需要定制时）：
PORT=8890
while ss -tln 2>/dev/null | grep -q ":$PORT "; do PORT=$((PORT + 1)); done   # 自动避让
node /tmp/tailscale-remote-serve.mjs > /tmp/tailscale-remote-serve.log 2>&1 &   # 脚本由 serve.sh 生成
echo $! > /tmp/tailscale-remote-serve.pid
curl --noproxy '*' -s -o /dev/null -w "%{http_code}" "http://${SERVER_TAILSCALE_IP}:${PORT}/${PAGE}"   # 自检（直连，绕代理）
ssh $SSH_OPTS "$MAC_HOST" "open 'http://${SERVER_TAILSCALE_IP}:${PORT}/${PAGE}'"
```

### 服务管理

```bash
bash <skill目录>/scripts/cleanup.sh      # 一键停止（不用记端口/PID）
cat /tmp/tailscale-remote-serve.pid | xargs -r kill   # 等价手工方式
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

# 整目录（递归）；大目录优先 rsync（增量）
scp -r $SSH_OPTS /path/on/server/dir "$MAC_HOST":~/Downloads/
rsync -avz -e "ssh $SSH_OPTS" /path/on/server/dir "$MAC_HOST":~/Downloads/
```

## 用法三：远程执行本机命令

```bash
# 任意命令
ssh $SSH_OPTS "$MAC_HOST" 'echo hi; uname -a'

# 看本机是否有文件
ssh $SSH_OPTS "$MAC_HOST" 'ls ~/Downloads/ | head'

# 打开应用/访达
ssh $SSH_OPTS "$MAC_HOST" 'open -a "Finder" ~/Downloads'

# 非 macOS 本机：open → xdg-open（Linux）/ start（Windows cmd）
```
