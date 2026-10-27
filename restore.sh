#!/bin/bash
# arkplan/restore.sh — 从干净的宿主系统镜像重建到 2026-10-28 05:20 的状态
# 用法:  sudo bash arkplan/restore.sh
# 前提:  1) 同型号板子 + 同固件（uname -r == 5.10.0+）
#        2) 已 apt install waydroid（1.6.3）
#        3) 外部资产已拷回：system.img / vendor.img / APK（见 RESTORE.md §1）
set -u
ROOT=$(cd "$(dirname "$0")" && pwd)
SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"
WD=/var/lib/waydroid
IMG_SRC=${IMG_SRC:-/root/wd-img-backup-1027_2222}

say() { printf '\n\033[1;36m== %s ==\033[0m\n' "$*"; }
ok()  { printf '  \033[32m✔\033[0m %s\n' "$*"; }
bad() { printf '  \033[31m✘\033[0m %s\n' "$*"; }
warn(){ printf '  \033[33m!\033[0m %s\n' "$*"; }

say "0/7 内核版本校验（.ko 的 vermagic 是 5.10.0+）"
K=$(uname -r)
if [ "$K" = "5.10.0+" ]; then ok "内核 $K 匹配"
else bad "内核是 $K，与 .ko 的 vermagic(5.10.0+) 不符 —— 需要重编模块，先停下"
     warn "重编: src/binder-mod、src/ashmem-mod（NDK r26d + /lib/modules/\$(uname -r)/build）"
     exit 2
fi

say "1/7 Waydroid 是否安装"
if command -v waydroid >/dev/null; then ok "$(waydroid --version 2>/dev/null || echo installed)"; else bad "缺 waydroid，先 apt install waydroid"; exit 3; fi

say "2/7 安卓镜像（2.3G，不在 git 里）"
mkdir -p "$WD/images"
if [ -f "$IMG_SRC/system.img" ] && [ -f "$IMG_SRC/vendor.img" ]; then
  $SUDO ln -sfn "$IMG_SRC/system.img" "$WD/images/system.img"
  $SUDO ln -sfn "$IMG_SRC/vendor.img" "$WD/images/vendor.img"
  ok "已软链到 $IMG_SRC"
else
  bad "$IMG_SRC 下没有 system.img/vendor.img"
  warn "从仓库外拷回: system.img md5 410bb605bc27b0a0610b924555bfba08 (1.9G)"
  warn "            vendor.img md5 4ba49f5ea81523ec9db9d9ef6fa3df32 (403M)"
  exit 4
fi

say "3/7 waydroid.cfg（arch=arm64_only / binder_protocol=aidl3 / mount_overlays）"
$SUDO mkdir -p "$WD"
[ -f "$WD/waydroid.cfg" ] && $SUDO cp -f "$WD/waydroid.cfg" "$WD/waydroid.cfg.bak.$(date +%m%d_%H%M)"
$SUDO cp -f "$ROOT/state/etc/waydroid.cfg" "$WD/waydroid.cfg" && ok "waydroid.cfg 已恢复"

say "4/7 安卓系统内的改动（overlay_rw）"
# 只回放真实改动；cgroup.procs 是运行时垃圾，不要复制
$SUDO mkdir -p "$WD/overlay_rw/system/lib64" "$WD/overlay_rw/system/etc/init" \
     "$WD/overlay_rw/system/system/apex/com.android.art/lib64"
$SUDO cp -f "$ROOT/state/overlay_rw_system/lib64/libart.so" "$WD/overlay_rw/system/lib64/libart.so"
$SUDO cp -f "$ROOT/state/overlay_rw_system/lib64/libart.so" \
     "$WD/overlay_rw/system/system/apex/com.android.art/lib64/libart.so"
$SUDO cp -f "$ROOT/state/overlay_rw_system/etc/init/vold.rc" "$WD/overlay_rw/system/etc/init/vold.rc"
ok "libart.so（UFFD 修复）+ vold.rc 已回放"

say "5/7 waydroid-net.sh（被改过，出网靠它）"
T=/usr/lib/waydroid/data/scripts/waydroid-net.sh
if [ -f "$T" ]; then
  $SUDO cp -f "$T" "$T.orig.$(date +%m%d_%H%M)"
  $SUDO cp -f "$ROOT/state/etc/waydroid-net.sh.modified" "$T"
  $SUDO chmod +x "$T"
  ok "已替换（md5 应为 1a522e267df454fae8929be7af83d808）"
  md5sum "$T"
else
  warn "目标不存在: $T（waydroid 包未装好？）"
fi

say "6/7 宿主侧 systemd 单元"
$SUDO cp -f "$ROOT/state/etc/wdroot2.service" /etc/systemd/system/wdroot2.service
$SUDO systemctl daemon-reload && ok "wdroot2.service 已安装（oneshot，调 launcher/wd_task2.sh）"

say "7/7 起容器 + 修宿主网络 + 等 adb"
bash "$ROOT/up.sh"
RC=$?
if [ $RC -eq 0 ]; then ok "up.sh 成功"; else bad "up.sh 返回 $RC，看上面输出"; fi

say "验证清单（手动确认）"
cat <<'EOF'
  uname -r                        -> 5.10.0+
  lsmod | grep -E "binder|ashmem" -> 三个模块在
  ls /dev/binder*                 -> binder binderfs hwbinder vndbinder
  waydroid status                 -> Session: RUNNING
  adb devices                     -> 192.168.240.112:5555  device
  adb -s 192.168.240.112:5555 shell getprop sys.boot_completed -> 1
  adb -s 192.168.240.112:5555 shell ping -c2 8.8.8.8            -> 通则出网正常
EOF
