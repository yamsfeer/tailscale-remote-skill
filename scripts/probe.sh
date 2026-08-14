#!/usr/bin/env bash
# tailscale-remote · 首次探测脚本
# 作用：自动定位 服务器 IP / 本机(Mac) IP / 可用 SSH 用户名，写入 ~/.tailscale-remote.env。
# 之后每次使用前 `source ~/.tailscale-remote.env` 即可，无需重复排查。
#
# 重要：tailscale status 的 User 列是「Tailscale 账户 email 前缀」，不是 SSH 用户名。
# SSH 用户名 = 本机操作系统登录名。本脚本只尝试本机当前用户 + 常见候选（纯公钥认证，无爆破）。
set -u

ENV_FILE="$HOME/.tailscale-remote.env"

# 已有配置 → 直接复用（避免每次重新探测）
if [ -f "$ENV_FILE" ]; then
  echo "✓ 已有配置：$(tr '\n' ' ' < "$ENV_FILE")"
  echo "  使用前执行: source $ENV_FILE"
  exit 0
fi

echo "── 首次探测（结果将持久化到 $ENV_FILE）──"

SERVER_IP=$(tailscale ip -4 2>/dev/null | head -1)
MAC_IP=$(tailscale status 2>/dev/null | awk '$4 ~ /macOS/ {print $1; exit}')

echo "· 服务器 Tailscale IP: ${SERVER_IP:-(未获取到)}"
echo "· 本机(Mac) Tailscale IP: ${MAC_IP:-(未发现 macOS 节点)}"
[ -z "$SERVER_IP" ] && echo "✗ 服务器不在 Tailscale 网络，先执行 tailscale up" && exit 1
[ -z "$MAC_IP" ] && echo "✗ 未发现 macOS 节点，确认本机桌面端已登录 Tailscale" && exit 1

# 候选用户名：① 服务器当前用户（同构环境最常见）② 常见登录名 ③ 手动指定
# 可在此按你的环境补充常用登录名（例：添加 "macbook"）
CANDIDATES=("${USER:-}" "admin" "user")
for u in "${CANDIDATES[@]}"; do
  [ -z "$u" ] && continue
  if ssh -o BatchMode=yes -o ConnectTimeout=4 -o StrictHostKeyChecking=accept-new "$u@$MAC_IP" 'echo ok' >/dev/null 2>&1; then
    echo "✓ SSH 用户名命中: $u"
    cat > "$ENV_FILE" << EOF
# tailscale-remote 配置（由探测脚本生成，可手动修改）
export MAC_HOST="$u@$MAC_IP"
export MAC_TAILSCALE_IP="$MAC_IP"
export SERVER_TAILSCALE_IP="$SERVER_IP"
EOF
    echo "✓ 已写入 $ENV_FILE"
    echo "  使用前执行: source $ENV_FILE"
    exit 0
  fi
done

echo "✗ 未探测到可用 SSH 用户名。请检查："
echo "  1. 本机开启远程登录（macOS：系统设置 → 通用 → 共享 → 远程登录）"
echo "  2. 服务器公钥已加入本机 ~/.ssh/authorized_keys（服务器: cat ~/.ssh/id_*.pub）"
echo "  3. 手动测试: ssh -o BatchMode=yes <你的Mac登录名>@$MAC_IP 'echo ok'"
echo "     找到正确用户名后，手动创建 $ENV_FILE 即可跳过探测。"
exit 1
