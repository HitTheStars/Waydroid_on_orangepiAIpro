#!/bin/sh
# arkplan · 容器内网络验证（在容器内执行，需要 root）
# 用法： sudo lxc-attach -P /var/lib/waydroid/lxc -n waydroid -- sh /data/local/tmp/verify_net.sh
# 或直接在宿主机跑 arkplan/net/run_verify.sh
set -u
echo "== boot =="
echo "sys.boot_completed=$(getprop sys.boot_completed)"
for s in surfaceflinger zygote audioserver vendor.audio-hal bootanim; do
    printf 'init.svc.%s=%s\n' "$s" "$(getprop init.svc.$s)"
done

echo "== ip addr (eth0) =="
ip -o addr show eth0

echo "== ip route (main) =="
ip route

echo "== ip route table eth0  <-- 默认路由必须在这里，main 表里有也没用 =="
ip route show table eth0

echo "== ip rule (tail) =="
ip rule | tail -8

echo "== ping 网关 =="
ping -c2 -W3 192.168.240.1 2>&1 | tail -2

echo "== ping 外网 IP（验路由，不涉 DNS）=="
ping -c2 -W3 223.5.5.5 2>&1 | tail -2

echo "== 解析域名（验 DNS）=="
ping -c1 -W3 www.baidu.com 2>&1 | head -2

echo "== https（验 TLS + 全链路）=="
curl -sI -m 15 https://www.baidu.com 2>&1 | head -4

echo "== 连通性验证状态（PARTIAL_CONNECTIVITY 说明 captive portal 探测没通）=="
timeout 25 dumpsys connectivity 2>/dev/null | grep -oE "PARTIAL_CONNECTIVITY|VALIDATED" | sort | uniq -c
