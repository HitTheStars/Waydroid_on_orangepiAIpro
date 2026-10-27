#!/bin/bash
# arkplan/scripts/pack_assets.sh — 给仓库外的二进制资产生成校验清单 + 导出打包指引
# 用法: sudo bash arkplan/scripts/pack_assets.sh
# 产物: arkplan/state/assets.sha256（可提交，用于异地副本的完整性校验）
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"
OUT="$ROOT/state/assets.sha256"
IMG_SRC=${IMG_SRC:-/root/wd-img-backup-1027_2222}

FILES=(
  "$IMG_SRC/system.img"
  "$IMG_SRC/vendor.img"
  "/home/HwHiAiUser/data/arkplan/apk/arknights-hg-2781.apk"
  "$ROOT/src/binder-nofs2/binder_linux_nofs.ko"
  "$ROOT/src/binder-mod/binder_linux.ko"
  "$ROOT/src/ashmem-mod/ashmem_mod.ko"
  "$ROOT/state/overlay_rw_system/lib64/libart.so"
  "$ROOT/state/etc/waydroid-net.sh.modified"
)

: > "$OUT.tmp"
{
  echo "# arkplan 资产校验清单  生成于 $(date '+%F %T')"
  echo "# 用法: sha256sum -c assets.sha256    (缺失/路径不同时用 --ignore-missing)"
} >> "$OUT.tmp"

for f in "${FILES[@]}"; do
  if $SUDO test -f "$f"; then
    sz=$($SUDO stat -c%s "$f")
    printf '  %-72s %6.1f MB  计算 sha256...\n' "$(basename "$f")" "$(echo "scale=1;$sz/1048576" | bc)"
    h=$($SUDO sha256sum "$f" | awk '{print $1}')
    printf '%s  %s  %s\n' "$h" "$sz" "$f" >> "$OUT.tmp"
    printf '    → %s\n' "$h"
  else
    printf '  \033[33m跳过（不存在）\033[0m %s\n' "$f"
    printf '# MISSING: %s\n' "$f" >> "$OUT.tmp"
  fi
done
mv -f "$OUT.tmp" "$OUT"
$SUDO chown $(id -u):$(id -g) "$OUT" 2>/dev/null

cat <<EOF

已写入: $OUT

异地备份（在 PC 上执行，别在板子上复制——同一块盘没意义）:
  mkdir -p ~/arkplan-assets
  scp HwHiAiUser@<板子IP>:$IMG_SRC/{system,vendor}.img ~/arkplan-assets/
  scp HwHiAiUser@<板子IP>:/home/HwHiAiUser/data/arkplan/apk/arknights-hg-2781.apk ~/arkplan-assets/
  scp HwHiAiUser@<板子IP>:$OUT ~/arkplan-assets/

校验（在 PC 上）:
  cd ~/arkplan-assets && sed 's#/.*/##' assets.sha256 | sha256sum -c --

恢复时放回:
  sudo mkdir -p $IMG_SRC && sudo cp ~/arkplan-assets/*.img $IMG_SRC/
  cp ~/arkplan-assets/arknights-hg-2781.apk /home/HwHiAiUser/data/arkplan/apk/
  sudo bash $ROOT/restore.sh
EOF
