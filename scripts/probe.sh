#!/usr/bin/env bash
# tailscale-remote · 首次探测脚本
# 作用：自动定位 服务器 IP / 本机(Mac) IP / 可用 SSH 用户名，
#       写入 skill 目录下的 tailscale-remote.env（与 SKILL.md 同级，不散落 home 目录）。
# 之后每次使用前 `source <skill目录>/tailscale-remote.env` 即可，无需重复排查。
#
# 重要：tailscale status 的 User 列是「Tailscale 账户 email 前缀」，不是 SSH 用户名。
# SSH 用户名 = 本机操作系统登录名。本脚本只尝试本机当前用户 + 常见候选（纯公钥认证，无爆破）。
set -u

# 打码显示 IP（终端回显/日志不泄漏完整地址，配置文件中仍是完整值）
mask_ip() {
  echo "$1" | awk -F. 'NF==4 {print $1"."$2".***.***"; exit} {print "***"}'
}

# 自定位 skill 目录：本脚本位于 <skill>/scripts/ 下，配置写在 skill 根（与 SKILL.md 同级）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$SKILL_DIR/tailscale-remote.env"
LEGACY_ENV_FILE="$HOME/.tailscale-remote.env"

# 迁移：v2 时代配置在 ~/.tailscale-remote.env，收敛到 skill 目录后删除旧文件
if [ -f "$LEGACY_ENV_FILE" ] && [ ! -f "$ENV_FILE" ]; then
  cp "$LEGACY_ENV_FILE" "$ENV_FILE" && chmod 600 "$ENV_FILE" && rm -f "$LEGACY_ENV_FILE"
  echo "✓ 已从 $LEGACY_ENV_FILE 迁移配置到 $ENV_FILE（旧文件已删除）"
fi

# 已有配置 → 直接复用（只提示路径，不回显明文 IP/用户名）
if [ -f "$ENV_FILE" ]; then
  echo "✓ 已有配置：$ENV_FILE"
  echo "  使用前执行: source $ENV_FILE"
  exit 0
fi

echo "── 首次探测（结果将写入 $ENV_FILE，权限 600）──"

SERVER_IP=$(tailscale ip -4 2>/dev/null | head -1)
MAC_IP=$(tailscale status 2>/dev/null | awk '$4 ~ /macOS/ {print $1; exit}')

if [ -n "$SERVER_IP" ]; then
  echo "· 服务器 Tailscale IP: $(mask_ip "$SERVER_IP")"
else
  echo "· 服务器 Tailscale IP: (未获取到)"
fi
if [ -n "$MAC_IP" ]; then
  echo "· 本机(Mac) Tailscale IP: $(mask_ip "$MAC_IP")"
else
  echo "· 本机(Mac) Tailscale IP: (未发现 macOS 节点)"
fi
[ -z "$SERVER_IP" ] && echo "✗ 服务器不在 Tailscale 网络，先执行 tailscale up" && exit 1
[ -z "$MAC_IP" ] && echo "✗ 未发现 macOS 节点，确认本机桌面端已登录 Tailscale" && exit 1

# 候选用户名：① 服务器当前用户（同构环境最常见）② 常见登录名 ③ 手动指定
# 可在此按你的环境补充常用登录名（例：添加 "macbook"）
CANDIDATES=("${USER:-}" "admin" "user")
for u in "${CANDIDATES[@]}"; do
  [ -z "$u" ] && continue
  if ssh -o BatchMode=yes -o ConnectTimeout=4 -o StrictHostKeyChecking=accept-new "$u@$MAC_IP" 'echo ok' >/dev/null 2>&1; then
    echo "✓ SSH 用户名命中: $u"
    umask 177
    cat > "$ENV_FILE" << EOF
# tailscale-remote 配置（由探测脚本生成，可手动修改；请勿提交进 git）
export MAC_HOST="$u@$MAC_IP"
export MAC_TAILSCALE_IP="$MAC_IP"
export SERVER_TAILSCALE_IP="$SERVER_IP"
EOF
    chmod 600 "$ENV_FILE"
    echo "✓ 已写入 $ENV_FILE"
    echo "  使用前执行: source $ENV_FILE"
    exit 0
  fi
done

echo "✗ 未探测到可用 SSH 用户名。请检查："
echo "  1. 本机开启远程登录（macOS：系统设置 → 通用 → 共享 → 远程登录）"
echo "  2. 服务器公钥已加入本机 ~/.ssh/authorized_keys（服务器: cat ~/.ssh/id_*.pub）"
echo "  3. 手动测试: ssh -o BatchMode=yes <你的Mac登录名>@$(mask_ip "$MAC_IP") 'echo ok'"
echo "     找到正确用户名后，手动创建 $ENV_FILE 即可跳过探测。"
exit 1
