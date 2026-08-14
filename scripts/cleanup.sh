#!/usr/bin/env bash
# cleanup.sh · 一键停止本 skill 启动的静态服务
# 无需记得端口 / PID：读取 PID 文件，进程活着就杀，顺手删 PID 文件。
set -u

PID_FILE="/tmp/tailscale-remote-serve.pid"

if [ ! -f "$PID_FILE" ]; then
  echo "· 没有运行中的服务（无 PID 文件）"
  exit 0
fi

PID=$(cat "$PID_FILE" 2>/dev/null)
if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
  kill "$PID" 2>/dev/null && echo "✓ 已停止服务 (PID $PID)"
else
  echo "· 进程已不存在，仅清理 PID 文件"
fi
rm -f "$PID_FILE"
