#!/bin/bash
set -u
S="lxc-attach -P /var/lib/waydroid/lxc -n waydroid --"
echo "=== svc 状态 ==="
for s in zygote surfaceflinger audioserver vendor.audio-hal bootanim; do
  printf "  %-18s %s\n" "$s" "$($S getprop init.svc.$s 2>/dev/null)"
done
printf "  boot_completed = [%s]\n" "$($S getprop sys.boot_completed 2>/dev/null)"
echo "=== HIDL 注册 ==="
$S service list 2>/dev/null | grep -iE "audio|effect" | head
echo "=== 32 位进程 ==="
n=0
for p in $($S ps -A -o PID 2>/dev/null | tail -n +2); do
  e=$($S readlink /proc/$p/exe 2>/dev/null) || continue
  [ -z "$e" ] && continue
  h=$($S od -An -tx1 -N5 "$e" 2>/dev/null | tr -d ' \n')
  if [ "$h" = "7f454c4601" ]; then
    echo "  32bit pid=$p $($S cat /proc/$p/comm 2>/dev/null) -> $e"
    n=$((n+1))
  fi
done
echo "  32 位进程数 = $n"
echo "=== 剩余 32 位可执行文件 ==="
R=/var/lib/waydroid/rootfs
for f in "$R"/vendor/bin/hw/* "$R"/vendor/bin/*; do
  [ -f "$f" ] || continue
  h=$(od -An -tx1 -N5 "$f" 2>/dev/null | tr -d ' \n')
  [ "$h" = "7f454c4601" ] && echo "  ${f#$R}"
done
echo "=== audio-hal 相关日志尾部 ==="
$S logcat -b main -d 2>/dev/null | grep -iE "audio-hal|AudioFlinger|audio_policy" | tail -8
echo "=== minigbm / gralloc 崩溃 ==="
$S logcat -b crash -d 2>/dev/null | tail -25
