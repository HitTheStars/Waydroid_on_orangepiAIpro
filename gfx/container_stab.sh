#!/system/bin/sh
# 在容器内跑，采样稳定性
N=${1:-6}
for i in $(seq 1 $N); do
  echo "=== $(date +%H:%M:%S) bc=$(getprop sys.boot_completed) ba=$(getprop init.svc.bootanim) sf=$(getprop init.svc.surfaceflinger)"
  ps -A -o PID,NAME | grep -E 'system_server|systemui|bootanimation|keystore2|zygote' | tr '\n' ' '
  echo
  echo "crashFATAL=$(/system/bin/logcat -d -b crash | grep -c 'FATAL EXCEPTION')"
  sleep 10
done
