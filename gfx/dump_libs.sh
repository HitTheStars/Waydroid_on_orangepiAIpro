#!/bin/bash
# 把 vendor 里跟图形相关的 .so 拷到宿主机 /tmp/gfxdump 做符号分析（不改镜像）
set -e
OUT=/tmp/gfxdump
mkdir -p "$OUT"
V=/var/lib/waydroid/rootfs/vendor
for f in lib64/libminigbm_gralloc_gbm_mesa.so lib64/libgbm_mesa.so lib64/libgbm_mesa_wrapper.so \
         lib64/dri_gbm.so lib64/libgallium_dri.so \
         lib64/hw/android.hardware.graphics.mapper@4.0-impl.minigbm_gbm_mesa.so \
         lib64/hw/gralloc.gbm.so lib64/hw/gralloc.minigbm_gbm_mesa.so lib64/hw/gralloc.default.so \
         lib64/hw/android.hardware.graphics.mapper@2.0-impl-2.1.so \
         lib64/hw/android.hardware.graphics.allocator@2.0-impl.so \
         lib64/hw/hwcomposer.waydroid.so lib64/libEGL_mesa.so lib64/libGLESv1_CM_mesa.so lib64/libGLESv2_mesa.so ; do
  [ -f "$V/$f" ] && cp -f "$V/$f" "$OUT/$(basename "$f")" || true
done
ls -la "$OUT"
