#!/bin/bash
# 干净测试：容器重启后，不设任何 setprop，adbd 会不会自己监听 5555
set -uo pipefail
export WAYLAND_DISPLAY=wayland-0 DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 XDG_SESSION_TYPE=wayland
T=192.168.240.112:5555
say(){ printf "\n== %s ==\n" "$*"; }

say "重启前：把 service.adb.tcp.port 清掉，确保测的是『自启』而不是残留"
timeout 8 adb -s "$T" shell "setprop service.adb.tcp.port ''; getprop service.adb.tcp.port; getprop persist.adb.tcp.port" 2>&1

say "停 session / 重启容器 / 起 session（不做任何 adb 操作）"
waydroid session stop >/dev/null 2>&1 || true
sleep 2
printf '%s\n' "${SUDO_PASS:-}" | sudo -S -p '' systemctl restart waydroid-container 2>/dev/null
START=$(date +%s)
sleep 5
setsid nohup waydroid session start > /tmp/wd_autostart_session.log 2>&1 &
adb kill-server >/dev/null 2>&1

say "每 5 秒试一次 adb connect（上限 150s）"
state=""
for i in $(seq 1 30); do
  adb start-server >/dev/null 2>&1
  adb connect "$T" >/dev/null 2>&1
  state=$(adb devices | awk -v t="$T" '$1==t {print $2}')
  now=$(( $(date +%s) - START ))
  printf "  t+%03ds  state=%s\n" "$now" "${state:-none}"
  case "$state" in device|unauthorized) break ;; esac
  sleep 5
done

say "结果"
if [ "$state" = "device" ] || [ "$state" = "unauthorized" ]; then
  echo "  ✅ adbd 自启了（t+$(( $(date +%s) - START ))s，state=$state）"
  [ "$state" = "unauthorized" ] && echo "  ⚠️  但弹了授权框：adb_keys 没被认，需要点 Allow"
else
  echo "  ❌ 150s 内没起来 → 5555 不自动开，up.sh 里那一手 setprop 是必需的"
fi
echo "  service.adb.tcp.port（若 adb 通）= $(timeout 8 adb -s "$T" shell getprop service.adb.tcp.port 2>/dev/null | tr -d '\r')"
