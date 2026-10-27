#!/bin/bash
# Waydroid 图形层/boot_completed 修复（2026-10-28）
# 幂等，可重复跑。全部是宿主机 + overlay / overlay_rw 改动，不动 /usr/share/waydroid-extra/images/*.img
# 用法: sudo bash arkplan/gfx/fix_boot.sh    （密码用你自己的渠道给，不要写进文件）
set -euo pipefail
W=/var/lib/waydroid
DATA=/home/HwHiAiUser/.local/share/waydroid/data   # 容器 /data（uid 数值直通）

echo "== 1) /dev/dri/renderD128 权限"
# 容器里 gid 109 = 宿主机 render 组，Android 侧不存在该组；Android 进程 open() 直接 EACCES
# Waydroid 自己会 chmod 777，但容器启动过程中宿主机 udev 会把 0660 重新盖回来 → 用 udev 规则钉死
cat > /etc/udev/rules.d/90-waydroid-render.rules <<'EOF'
# Waydroid: 让容器内 Android 进程能打开 panfrost render node
SUBSYSTEM=="drm", KERNEL=="renderD*", MODE="0666"
EOF
udevadm control --reload-rules
udevadm trigger --subsystem-match=drm --action=change || true
chmod 666 /dev/dri/renderD* || true
ls -ln /dev/dri/

echo "== 2) odm build.prop abilist（32 位毒瘤，会让 system_server 去找 zygote_secondary）"
SRC=$W/rootfs/vendor/odm/etc/build.prop
DST=$W/overlay/vendor/odm/etc/build.prop
mkdir -p "$(dirname "$DST")"
[ -f "$DST" ] || cp -f "$SRC" "$DST"
sed -i 's/^ro\.odm\.product\.cpu\.abilist=.*/ro.odm.product.cpu.abilist=arm64-v8a/'      "$DST"
sed -i 's/^ro\.odm\.product\.cpu\.abilist32=.*/ro.odm.product.cpu.abilist32=/'           "$DST"
sed -i 's/^ro\.odm\.product\.cpu\.abilist64=.*/ro.odm.product.cpu.abilist64=arm64-v8a/'  "$DST"
grep -n abilist "$DST"

echo "== 3) keystore2 数据库属主（之前被误留成 1000:1000，keystore2=1017 打不开 → LockSettingsService AssertionError 4）"
KS=$DATA/misc/keystore
if [ -d "$KS" ]; then
  chown 1017:1017 "$KS"/*.sqlite 2>/dev/null || true
  chmod 600 "$KS"/*.sqlite 2>/dev/null || true
  ls -ln "$KS"
fi

echo "== 4) drop cache（overlay lowerdir 内容变更后必做）"
echo 3 > /proc/sys/vm/drop_caches || true

echo "完成。接下来：bash arkplan/gfx/restart_session.sh，再跑容器内 arkplan/gfx/container_verify.sh"
