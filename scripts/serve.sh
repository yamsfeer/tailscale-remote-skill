#!/usr/bin/env bash
# serve.sh · 一键起静态服务并在本机浏览器打开
# 用法: bash scripts/serve.sh <html目录> [入口页] [--open] [--ttl 分钟]
# 特性:
#   · 自动避让占用端口（8890 起 +1）
#   · 启动前自动杀掉上次残留服务（PID 文件单实例语义）
#   · 滑动过期：无访问 TTL 分钟（默认 15）自动退出，不会无限残留
#   · --open 自动在本机浏览器打开（自动识别 open / xdg-open / start）
#   · curl 自检 + PID 持久化（/tmp/tailscale-remote-serve.pid）
set -u

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$SKILL_DIR/tailscale-remote.env"
if [ ! -f "$ENV_FILE" ]; then
  echo "✗ 未找到配置 $ENV_FILE，先运行: bash $SKILL_DIR/scripts/probe.sh"
  exit 1
fi
source "$ENV_FILE"

HTML_DIR="${1:-}"
if [ -z "$HTML_DIR" ]; then
  echo "用法: bash scripts/serve.sh <html目录> [入口页] [--open] [--ttl 分钟]"
  echo "示例: bash scripts/serve.sh /tmp/preview index.html --open"
  exit 1
fi
HTML_DIR="$(cd "$HTML_DIR" && pwd)" || exit 1
PAGE="index.html"
OPEN=0
TTL=15
shift
# while 循环而非 for：循环体内 shift 才会生效，避免 --ttl 的值被当成参数
while [ $# -gt 0 ]; do
  case "$1" in
    --open) OPEN=1; shift ;;
    --ttl) TTL="$2"; shift 2 ;;
    *) PAGE="$1"; shift ;;
  esac
done

# 路径含单引号会破坏 node 内插，直接报错（极罕见）
case "$HTML_DIR$PAGE" in
  *"'"*) echo "✗ 路径含单引号，暂不支持"; exit 1 ;;
esac

SSH_OPTS="-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5"
PID_FILE="/tmp/tailscale-remote-serve.pid"
LOG_FILE="/tmp/tailscale-remote-serve.log"

# ── 杀掉上次残留（进程活着就 kill；死了只清 PID 文件）──
if [ -f "$PID_FILE" ]; then
  OLD_PID=$(cat "$PID_FILE" 2>/dev/null)
  if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
    echo "· 清理上次残留服务 (PID $OLD_PID)"
    kill "$OLD_PID" 2>/dev/null
    sleep 0.3
  fi
  rm -f "$PID_FILE"
fi

# ── 端口避让：8890 起，被占用 +1 ──
PORT=8890
while ss -tln 2>/dev/null | grep -q ":$PORT "; do PORT=$((PORT + 1)); done

# ── 生成服务脚本（内置滑动过期，无依赖）──
cat > /tmp/tailscale-remote-serve.mjs << EOF
import http from 'node:http';
import { readFileSync, statSync, unlinkSync } from 'node:fs';
import { join, normalize, extname } from 'node:path';
const PORT = ${PORT}, HOST = '${SERVER_TAILSCALE_IP}', ROOT = '${HTML_DIR}', PAGE = '${PAGE}';
const TTL_MS = ${TTL} * 60 * 1000;
const MIME = { html: 'text/html; charset=utf-8', css: 'text/css', js: 'text/javascript', json: 'application/json', png: 'image/png', jpg: 'image/jpeg', jpeg: 'image/jpeg', gif: 'image/gif', svg: 'image/svg+xml', ico: 'image/x-icon', webp: 'image/webp', txt: 'text/plain', pdf: 'application/pdf', mp4: 'video/mp4', woff2: 'font/woff2', map: 'application/json' };
const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://x');
  const file = url.pathname === '/' ? '/' + PAGE : decodeURIComponent(url.pathname);
  const safe = normalize(join(ROOT, file));
  if (!(safe.startsWith(ROOT) && (safe.length === ROOT.length || safe[ROOT.length] === '/'))) {
    res.writeHead(403); res.end('403'); return;
  }
  try {
    statSync(safe);
    const body = readFileSync(safe);
    const ext = extname(safe).slice(1).toLowerCase();
    res.writeHead(200, { 'content-type': (MIME[ext] || 'application/octet-stream') });
    res.end(body);
  } catch { res.writeHead(404); res.end('404'); }
});
// 滑动过期：无访问 TTL 分钟自动退出（每次请求重置计时器）；退出时清理 PID 文件
let timer;
const expire = () => {
  console.log('[serve] 无访问 ' + ${TTL} + ' 分钟，自动退出');
  try { unlinkSync('/tmp/tailscale-remote-serve.pid'); } catch {}
  server.close();
  process.exit(0);
};
const touch = () => { clearTimeout(timer); timer = setTimeout(expire, TTL_MS); };
server.on('request', touch);
server.listen(PORT, HOST, () => { touch(); console.log('[serve] ready http://' + HOST + ':' + PORT + '/' + PAGE); });
EOF

node /tmp/tailscale-remote-serve.mjs > "$LOG_FILE" 2>&1 &
SERVE_PID=$!
echo "$SERVE_PID" > "$PID_FILE"
sleep 1

# ── 服务器端自检（非 200 先修这里，别急着开浏览器）──
# --noproxy '*'：直连 Tailscale IP，避免 http_proxy 干扰自检结果
CODE=$(curl --noproxy '*' -s -o /dev/null -w "%{http_code}" "http://${SERVER_TAILSCALE_IP}:${PORT}/${PAGE}" || echo "000")
if [ "$CODE" != "200" ]; then
  echo "✗ 自检失败 (HTTP $CODE)，日志见 $LOG_FILE"
  exit 1
fi

URL="http://${SERVER_TAILSCALE_IP}:${PORT}/${PAGE}"
echo "✓ 服务已启动: $URL"
echo "  · 无访问 ${TTL} 分钟自动退出（滑动过期）"
echo "  · 手动停止: bash $SKILL_DIR/scripts/cleanup.sh"
echo "  · PID: $SERVE_PID"

# ── 可选：在本机浏览器打开（自动识别本机平台）──
if [ "$OPEN" = "1" ]; then
  PLATFORM=$(ssh $SSH_OPTS "$MAC_HOST" 'uname -s' 2>/dev/null)
  case "$PLATFORM" in
    Linux) OPEN_CMD="xdg-open" ;;
    MINGW*|CYGWIN*|MSYS*) OPEN_CMD="cmd /c start" ;;
    *) OPEN_CMD="open" ;;
  esac
  ssh $SSH_OPTS "$MAC_HOST" "$OPEN_CMD '$URL'" && echo "✓ 已在本机浏览器打开"
fi
