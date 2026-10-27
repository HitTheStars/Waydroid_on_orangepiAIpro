#!/bin/bash
# arkplan/verify_restore.sh — 逐项验证"能否从干净系统恢复到当前状态"
# 用法: sudo bash arkplan/verify_restore.sh
# 退出码: 0 全绿 / 1 有 FAIL / 2 只有 WARN
set -u
ROOT=$(cd "$(dirname "$0")" && pwd)
SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"
WD=/var/lib/waydroid
IMG_SRC=${IMG_SRC:-/root/wd-img-backup-1027_2222}
APK=/home/HwHiAiUser/data/arkplan/apk/arknights-hg-2781.apk
P=0; F=0; W=0
pass(){ printf '  \033[32mPASS\033[0m %s\n' "$*"; P=$((P+1)); }
fail(){ printf '  \033[31mFAIL\033[0m %s\n' "$*"; F=$((F+1)); }
warn(){ printf '  \033[33mWARN\033[0m %s\n' "$*"; W=$((W+1)); }
sec(){ printf '\n\033[1;36m[%s]\033[0m\n' "$*"; }

sec "A. 仓库完整性（git 能重建的部分）"
cd "$ROOT" || exit 1
[ -z "$(git status --porcelain)" ] && pass "工作区干净，无未提交改动" || fail "工作区有未提交改动"
git rev-parse --verify HEAD >/dev/null 2>&1 && pass "HEAD = $(git log --oneline -1)" || fail "没有提交"
for r in $(git remote); do
  L=$(git rev-parse HEAD); R=$(git rev-parse "$r/$(git rev-parse --abbrev-ref HEAD)" 2>/dev/null || echo none)
  [ "$L" = "$R" ] && pass "已推送远程 $r" || fail "远程 $r 未同步（本地 $L / 远程 $R）"
done
for f in restore.sh RESTORE.md up.sh net/fix_host_net.sh STATUS.md \
         state/etc/waydroid.cfg state/etc/waydroid-net.sh.modified state/etc/wdroot2.service \
         state/overlay_rw_system/lib64/libart.so state/overlay_rw_system/etc/init/vold.rc; do
  [ -f "$f" ] && pass "仓库内 $f ($(stat -c%s "$f")B)" || fail "仓库缺 $f"
done
for k in src/binder-nofs2/binder_linux_nofs.ko src/binder-mod/binder_linux.ko src/ashmem-mod/ashmem_mod.ko; do
  [ -f "$k" ] && pass "模块 $k" || fail "模块缺 $k"
done
bash -n restore.sh 2>/dev/null && pass "restore.sh 语法通过" || fail "restore.sh 语法错误"

sec "B. 官方状态快照 vs 现网实际（能否原样回放）"
cmp -s state/etc/waydroid.cfg "$WD/waydroid.cfg" && pass "waydroid.cfg 与现网一致" || warn "waydroid.cfg 与现网不同（现网可能被手动改过，需重新捕获）"
cmp -s state/etc/waydroid-net.sh.modified /usr/lib/waydroid/data/scripts/waydroid-net.sh \
  && pass "waydroid-net.sh 与现网一致" || warn "waydroid-net.sh 与现网不同"
LIVE=$($SUDO md5sum "$WD/overlay_rw/system/lib64/libart.so" 2>/dev/null | awk '{print $1}')
REPO=$(md5sum state/overlay_rw_system/lib64/libart.so | awk '{print $1}')
[ "$LIVE" = "$REPO" ] && pass "libart.so 快照一致 ($REPO)" || warn "libart.so 现网=$LIVE 仓库=$REPO"

sec "C. 内核模块与当前内核匹配"
K=$(uname -r)
[ "$K" = "5.10.0+" ] && pass "内核 $K" || fail "内核 $K ≠ 5.10.0+，.ko 会 insmod 失败"
VM=$(modinfo -F vermagic src/binder-nofs2/binder_linux_nofs.ko 2>/dev/null | awk '{print $1}')
[ "$VM" = "$K" ] && pass "vermagic 匹配 ($VM)" || fail "vermagic $VM ≠ 内核 $K"
lsmod | grep -q binder && pass "binder 模块已加载" || warn "binder 未加载（恢复时会 insmod）"

sec "D. 仓库外的二进制资产（唯一一份，丢了就真没了）"
for n in system vendor; do
  f="$IMG_SRC/$n.img"
  if $SUDO test -f "$f"; then
    sz=$($SUDO stat -c%s "$f"); h=$($SUDO md5sum "$f" | awk '{print $1}')
    pass "$n.img ${sz}B md5=$h"
  else fail "$n.img 不在 $IMG_SRC"; fi
done
[ -f "$APK" ] && pass "APK $(stat -c%s "$APK")B" || fail "APK 不在 $APK"
[ -f "$ROOT/state/assets.sha256" ] && pass "资产 sha256 清单存在" || warn "还没有 sha256 清单（跑 scripts/pack_assets.sh）"

sec "E. 运行态（恢复目标）"
command -v waydroid >/dev/null && pass "waydroid $(waydroid --version 2>/dev/null)" || fail "waydroid 未安装"
waydroid status 2>/dev/null | grep -q RUNNING && pass "容器 RUNNING" || warn "容器未运行（恢复后应 RUNNING）"
ls /dev/binder >/dev/null 2>&1 && pass "/dev/binder 存在" || warn "/dev/binder 缺失"
T=192.168.240.112
adb devices 2>/dev/null | grep -q "$T" && pass "adb 已连 $T" || warn "adb 未连 $T"

sec "汇总"
printf '  PASS=%d  WARN=%d  FAIL=%d\n' "$P" "$W" "$F"
[ "$F" -gt 0 ] && { echo "  → 有 FAIL，干净系统恢复会卡住"; exit 1; }
[ "$W" -gt 0 ] && { echo "  → 无致命项，WARN 多为'当前未运行'的预期状态"; exit 2; }
echo "  → 全绿"; exit 0
