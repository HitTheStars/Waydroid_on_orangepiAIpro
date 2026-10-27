#!/bin/bash
# arkplan/up.sh —— Waydroid 一键起全套（宿主机侧，幂等，可反复跑）
#
# 实测结论（2026-10-28 03:22，干净重启验证）：
#   persist.adb.tcp.port=5555 已经让 adbd 开机自己监听 5555，t+44s 可连，state=device，
#   且 /data/misc/adb/adb_keys 持久 → 授权不重弹。
#   所以正常流程**不需要**再 setprop / 写 keys，那两个只在失联时做兜底。
#   lxc-attach 不可靠（容器常见的 lxc 锁 + 冻结会让它挂住），启动判定一律走 adb。
#
# 步骤：
#   1) insmod binder / ashmem（已加载则跳过）
#   2) 宿主侧修复：ufw + ip_forward、renderD128、overlay build.prop、keystore 属主
#   3) 重启容器 + 起 session（uid 1000 + 四个 env）
#   4) 等 adb 上线（<=150s），再等 sys.boot_completed=1
#   5) adb 兜底：unauthorized 才写 adb_keys；连不上才 setprop 重开 adbd
#   6) 体检报告：boot / IP / 出网 / 焦点 / 截图
#
# 每步前自动过一遍 ensure_unfrozen()：suspend_action=freeze 会让容器在无前台窗口时被冻结，
# 此时 adb 的 TCP 仍显示 device 但 shell 全超时，不先解冻就会误判成"炸了"。
#
# 用法：
#   bash arkplan/up.sh                  # 全流程（无 SUDO_PASS 则交互问密码）
#   SUDO_PASS=xxx bash arkplan/up.sh    # 免交互
#   bash arkplan/up.sh --no-restart     # 不重启容器，只做修复 + 体检（日常复位）
#   bash arkplan/up.sh --no-adb         # 跳过 adb 相关
#   密码只在本进程内存里，不落盘。

set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WD_IP=${WD_IP:-192.168.240.112}
WD_ADB_PORT=${WD_ADB_PORT:-5555}
ADB_TARGET="$WD_IP:$WD_ADB_PORT"
LXC="lxc-attach -P /var/lib/waydroid/lxc -n waydroid"
ADB="adb -s $ADB_TARGET"

NO_RESTART=0
WITH_ADB=1
for a in "$@"; do
  case "$a" in
    --no-restart) NO_RESTART=1 ;;
    --no-adb)     WITH_ADB=0 ;;
    -h|--help)    sed -n '2,30p' "$0"; exit 0 ;;
  esac
done

say()  { printf "\n\033[1;36m== %s ==\033[0m\n" "$*"; }
ok()   { printf "  \033[1;32m✅ %s\033[0m\n" "$*"; }
bad()  { printf "  \033[1;31m❌ %s\033[0m\n" "$*"; }
warn() { printf "  \033[1;33m⚠️  %s\033[0m\n" "$*"; }
FAIL=0
fail() { bad "$*"; FAIL=1; }
adbstate() { adb devices 2>/dev/null | awk -v t="$ADB_TARGET" '$1==t {print $2}'; }

# suspend_action=freeze：没前台窗口时 LXC 被 cgroup 冻结，adbd 的 TCP 还挂着但 shell 全超时。
# 这不是故障，解冻就行；每次判活/体检前都过一遍。
ensure_unfrozen() {
  local st
  st=$(timeout 8 waydroid status 2>/dev/null)
  case "$st" in
    *"Container:	FROZEN"*|*"Container: FROZEN"*)
      warn "容器 FROZEN（无前台窗口触发 suspend_action=freeze）→ 解冻"
      sdo lxc-unfreeze -P /var/lib/waydroid/lxc -n waydroid >/dev/null 2>&1 \
        && ok "已解冻" || warn "解冻失败（容器可能还没起）"
      ;;
  esac
}

# ---------- sudo ----------
PASS=${SUDO_PASS:-}
if [ -z "$PASS" ] && ! sudo -n true 2>/dev/null; then
  read -rsp "sudo 密码（仅本进程使用，不写盘）: " PASS; echo
fi
sdo() {
  if [ -n "$PASS" ]; then printf '%s\n' "$PASS" | sudo -S -p '' "$@"
  else sudo -n "$@"; fi
}
sdo true 2>/dev/null || { fail "sudo 不可用，后面全废"; exit 1; }

# ========== 1) 内核模块 ==========
say "1/6 内核模块"
for pair in "binder_linux_nofs:src/binder-nofs2/binder_linux_nofs.ko" \
            "ashmem_mod:src/ashmem-mod/ashmem_mod.ko"; do
  name=${pair%%:*}; rel=${pair#*:}
  if lsmod | awk '{print $1}' | grep -qx "$name"; then
    ok "$name 已加载"
  elif sdo insmod "$ROOT/arkplan/$rel" 2>/dev/null; then
    ok "$name insmod 成功"
  else
    fail "$name insmod 失败（看 dmesg）"
  fi
done
[ -e /dev/binder ] && ok "/dev/binder 在" || warn "/dev/binder 还没出来（容器起了才有）"

# ========== 2) 宿主侧修复 ==========
say "2/6 宿主侧修复（网络 / 图形 / keystore）"
sdo bash "$ROOT/arkplan/net/fix_host_net.sh" >/tmp/wd_fixnet.log 2>&1 \
  && ok "网络修复（日志 /tmp/wd_fixnet.log）" || fail "网络修复失败（/tmp/wd_fixnet.log）"
sdo bash "$ROOT/arkplan/gfx/fix_boot.sh" >/tmp/wd_fixboot.log 2>&1 \
  && ok "图形/keystore 修复（日志 /tmp/wd_fixboot.log）" || fail "图形修复失败（/tmp/wd_fixboot.log）"

# ========== 3) 重启容器 + session ==========
if [ "$NO_RESTART" -eq 0 ]; then
  say "3/6 重启容器 + 起 session"
  export WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-0}
  export DISPLAY=${DISPLAY:-:0}
  export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/1000}
  export XDG_SESSION_TYPE=wayland
  waydroid session stop >/dev/null 2>&1 || true
  sleep 2
  sdo systemctl restart waydroid-container && ok "容器已重启" || fail "systemctl restart 失败"
  sleep 5
  setsid nohup waydroid session start > /tmp/waydroid_session.log 2>&1 &
  ok "session 已在后台起（日志 /tmp/waydroid_session.log）"
else
  say "3/6 跳过重启（--no-restart）"
fi

# ========== 4) 等 adb 上线 + boot_completed（走 adb，不碰 lxc-attach） ==========
BOOT_OK=0
if [ "$WITH_ADB" -eq 0 ]; then
  say "4/6 跳过 adb 等待（--no-adb）"
  sleep 40
else
  say "4/6 等 adbd 上线（<=150s，实测 ~44s）"
  command -v adb >/dev/null || { fail "宿主没装 adb"; WITH_ADB=0; }
fi

if [ "$WITH_ADB" -eq 1 ]; then
  ensure_unfrozen
  T0=$(date +%s); ST=""
  while [ $(( $(date +%s) - T0 )) -lt 150 ]; do
    adb start-server >/dev/null 2>&1
    ST=$(adbstate)
    case "$ST" in device|unauthorized) break ;; esac
    adb connect "$ADB_TARGET" >/dev/null 2>&1
    sleep 3
  done
  DT=$(( $(date +%s) - T0 ))
  case "$ST" in
    device)       ok "adb 上线 t+${DT}s，state=device（persist.adb.tcp.port 生效）" ;;
    unauthorized) warn "adb 上线 t+${DT}s，但 state=unauthorized（授权丢了，进第 5 步补）" ;;
    *)            fail "150s 内 adb 没上线（state='${ST:-none}'）" ;;
  esac

  if [ "$ST" = "device" ]; then
    B=""
    for i in $(seq 1 40); do
      B=$(timeout 6 $ADB shell getprop sys.boot_completed 2>/dev/null | tr -d '\r\n')
      [ "$B" = "1" ] && break
      sleep 2
    done
    if [ "$B" = "1" ]; then ok "sys.boot_completed=1"; BOOT_OK=1
    else fail "boot_completed 不是 1"; fi
  fi
fi

# ========== 5) adb 兜底 ==========
if [ "$WITH_ADB" -eq 1 ]; then
  say "5/6 adb 兜底（正常流程什么都不做）"
  ST=$(adbstate)
  if [ "$ST" = "unauthorized" ]; then
    warn "authorization 丢失 → 重写 adb_keys"
    [ -f "$HOME/.android/adbkey" ] || adb keygen "$HOME/.android/adbkey" >/dev/null 2>&1
    PUB=$(adb pubkey "$HOME/.android/adbkey" 2>/dev/null)
    TMPK="$ROOT/.wd_adbkey.tmp"
    printf '%s %s@%s\n' "$PUB" "$(hostname)" "$(hostname)" > "$TMPK"
    chmod 644 "$TMPK"
    # rootfs 从宿主侧只读，只能从容器内部写；内容由宿主 root 侧重定向进去
    sdo sh -c "$LXC -- /system/bin/sh -c 'mkdir -p /data/misc/adb; cat > /data/misc/adb/adb_keys; chown 1000:2000 /data/misc/adb/adb_keys; chmod 640 /data/misc/adb/adb_keys; stop adbd; sleep 1; start adbd'" < "$TMPK" >/dev/null 2>&1 \
      && ok "adb_keys 已重写（$(wc -c < "$TMPK") 字节）" || warn "adb_keys 重写失败"
    rm -f "$TMPK"
    sleep 3; adb kill-server >/dev/null 2>&1; adb connect "$ADB_TARGET" >/dev/null 2>&1; sleep 2
    ST=$(adbstate)
  fi

  if [ -z "$ST" ] || [ "$ST" = "offline" ]; then
    warn "adbd 没在 5555 → setprop + 重启 adbd 兜底"
    sdo $LXC -- /system/bin/sh -c \
      "setprop service.adb.tcp.port $WD_ADB_PORT; setprop persist.adb.tcp.port $WD_ADB_PORT; stop adbd; sleep 1; start adbd" \
      >/dev/null 2>&1
    sleep 4; adb kill-server >/dev/null 2>&1; adb connect "$ADB_TARGET" >/dev/null 2>&1; sleep 2
    ST=$(adbstate)
  fi

  case "$ST" in
    device) ok "adb 通道 OK（$ADB_TARGET）" ;;
    unauthorized)
      warn "还差人工点一下弹窗；也可以让我点（720x503 下坐标 180,243 + 519,311）"
      fail "adb 未授权" ;;
    *) fail "adb 仍不通（state='${ST:-none}'）" ;;
  esac
fi

# ========== 6) 体检 ==========
say "6/6 体检"
if [ "$WITH_ADB" -eq 1 ] && [ "$(adbstate)" = "device" ]; then
  ensure_unfrozen
  IPNOW=$(timeout 6 $ADB shell "ip -4 addr show eth0 2>/dev/null | grep -m1 'inet '" 2>/dev/null | tr -d '\r' | awk '{print $2}')
  [ -n "$IPNOW" ] && ok "容器 IP: $IPNOW" || warn "读不到容器 IP（waydroid status 里有）"
  timeout 8 $ADB shell "ping -c1 -W2 223.5.5.5 >/dev/null 2>&1" && ok "出网: ping 223.5.5.5 通" || fail "出网: ping 不通"
  SZ=$(timeout 6 $ADB shell wm size 2>/dev/null | tr -d '\r')
  [ -n "$SZ" ] && ok "$SZ"
  FOCUS=$(timeout 8 $ADB shell "dumpsys window | grep -m1 mCurrentFocus" 2>/dev/null | tr -d '\r' | sed 's/^ *//')
  [ -n "$FOCUS" ] && ok "焦点: $FOCUS"
  if timeout 10 $ADB exec-out screencap -p > /tmp/wd_up_shot.png 2>/dev/null; then
    ok "截图: /tmp/wd_up_shot.png ($(stat -c%s /tmp/wd_up_shot.png) B)"
  else warn "截图失败"; fi
else
  warn "adb 没通，容器内体检跳过（看桌面截图）"
fi

echo
if [ "$FAIL" -eq 0 ]; then
  printf "\033[1;32m=== 全绿，可以干活了 ===\033[0m\n"
  printf "  控制: bash arkplan/adb/wd.sh tap 170 337 | key 4 | shot out.png\n"
else
  printf "\033[1;31m=== 有项没过，看上面红字 ===\033[0m\n"
fi
exit "$FAIL"
