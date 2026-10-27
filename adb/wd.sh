#!/usr/bin/env bash
# Waydroid ADB 通道助手（2026-10-28 03:12 打通）
# 用法：
#   bash arkplan/adb/wd.sh tap 170 337        # 点
#   bash arkplan/adb/wd.sh swipe 360 400 360 150 300
#   bash arkplan/adb/wd.sh text "hello"       # 注意：只支持 ASCII，中文要 input keyevent 或 adb shell am
#   bash arkplan/adb/wd.sh key 4              # keyevent BACK
#   bash arkplan/adb/wd.sh shot out.png       # 原始截图（720x503，无 Weston 标题栏）
#   bash arkplan/adb/wd.sh sh "getprop ro.build.version.release"
#   bash arkplan/adb/wd.sh devices
set -uo pipefail

IP=${WD_IP:-192.168.240.112}
PORT=${WD_ADB_PORT:-5555}
TARGET="$IP:$PORT"

adb connect "$TARGET" >/dev/null 2>&1 || true

cmd=${1:-devices}
case "$cmd" in
  tap)    adb -s "$TARGET" shell input tap "$2" "$3" ;;
  swipe)  adb -s "$TARGET" shell input swipe "$2" "$3" "$4" "$5" "${6:-300}" ;;
  text)   adb -s "$TARGET" shell input text "$2" ;;
  key)    adb -s "$TARGET" shell input keyevent "$2" ;;
  shot)   adb -s "$TARGET" exec-out screencap -p > "${2:-shot.png}" && echo "saved ${2:-shot.png}" ;;
  sh)     shift; adb -s "$TARGET" shell "$*" ;;
  *)      adb -s "$TARGET" "$@" ;;
esac
