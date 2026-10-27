#!/system/bin/sh
# 容器内跑，产出图形层修复的验证证据
echo "=== date"; date
echo "=== props"
for p in sys.boot_completed ro.hardware.gralloc ro.hardware.egl ro.hardware.vulkan \
         ro.product.cpu.abilist ro.product.cpu.abilist32 ro.zygote; do
  echo "$p = $(getprop $p)"
done
echo "=== services"
for s in zygote surfaceflinger bootanim audioserver vendor.audio-hal vndservicemanager; do
  echo "init.svc.$s = $(getprop init.svc.$s)"
done
echo "=== /dev/dri"
ls -ln /dev/dri/
echo "=== crash buffer: gbm_mesa_bo_import / FATAL counts"
echo "gbm_mesa_bo_import = $(/system/bin/logcat -d -b crash | grep -c gbm_mesa_bo_import)"
echo "FATAL EXCEPTION    = $(/system/bin/logcat -d -b crash | grep -c 'FATAL EXCEPTION')"
echo "crash lines total  = $(/system/bin/logcat -d -b crash | wc -l)"
echo "=== procs"
ps -A -o PID,NAME | grep -E 'system_server|systemui|surfaceflinger|zygote|bootanim|keystore2'
echo "=== ELFCLASS32 process count"
cnt=0
for p in /proc/[0-9]*; do
  c=$(dd if=$p/exe bs=1 skip=4 count=1 2>/dev/null | od -An -tu1 2>/dev/null | tr -d ' \n')
  [ "$c" = "1" ] && cnt=$((cnt+1))
done
echo "ELFCLASS32 processes = $cnt"
echo "=== done"
