#!/bin/bash
set -u
S="lxc-attach -P /var/lib/waydroid/lxc -n waydroid --"
echo "=== gralloc / egl 属性 ==="
for p in ro.hardware.gralloc ro.hardware.egl ro.hardware.vulkan ro.hardware ro.board.platform ro.hardware.gralloc4 debug.egl.hw; do
  printf "  %-24s [%s]\n" "$p" "$($S getprop $p 2>/dev/null)"
done
echo "=== vendor/lib64/hw 里 gralloc/mapper/allocator ==="
ls -la /var/lib/waydroid/rootfs/vendor/lib64/hw/ 2>/dev/null | grep -iE "gralloc|mapper|allocator|memtrack"
echo "=== 有没有非 mesa 的 minigbm ==="
ls -la /var/lib/waydroid/rootfs/vendor/lib64/ 2>/dev/null | grep -iE "minigbm|gbm"
echo "=== gralloc 服务状态 ==="
for s in vendor.graphics.allocator-4-0 vendor.graphics.mapper-4-0 graphics.allocator-4-0; do
  printf "  %-32s [%s]\n" "$s" "$($S getprop init.svc.$s 2>/dev/null)"
done
echo "=== 一次完整崩溃栈（第一个 pid）==="
awk '/F DEBUG   :       #00/{c++} c==1' /tmp/crash_before.txt | head -30
