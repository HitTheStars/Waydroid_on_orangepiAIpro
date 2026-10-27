#!/bin/bash
# 干净重启 Waydroid：session stop -> systemctl restart waydroid-container -> 以 uid 1000 后台起 session
# 用法: bash arkplan/gfx/restart_session.sh
# 注意: 需要当前用户能 sudo 重启服务；session 必须以 HwHiAiUser 身份跑（Wayland/Wayland socket 属于 1000）
set -x
export WAYLAND_DISPLAY=wayland-0
export DISPLAY=:0
export XDG_RUNTIME_DIR=/run/user/1000
export XDG_SESSION_TYPE=wayland

waydroid session stop || true
sleep 2
sudo systemctl restart waydroid-container
sleep 5
nohup setsid waydroid session start > /tmp/waydroid_session.log 2>&1 &
sleep 8
waydroid status
