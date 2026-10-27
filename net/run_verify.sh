#!/bin/bash
# arkplan · 在宿主机上跑「容器内验证」（把 verify_net.sh 灌进容器再执行，不落盘到 img）
# 用法: bash arkplan/net/run_verify.sh
set -eu
BASE="$(cd "$(dirname "$0")" && pwd)"
LXC="sudo lxc-attach -P /var/lib/waydroid/lxc -n waydroid"

# WARN: 容器 FROZEN 时 lxc-attach 会挂住，先看状态
if ! sudo waydroid status 2>/dev/null | grep -q "Container:.*RUNNING"; then
    echo "[!] 容器不是 RUNNING，先解冻/起会话："
    echo "    sudo lxc-unfreeze -P /var/lib/waydroid/lxc -n waydroid"
    echo "    sudo systemctl restart waydroid-container && waydroid session start"
    exit 1
fi

$LXC -- sh -c "cat > /data/local/tmp/verify_net.sh" < "$BASE/verify_net.sh"
$LXC -- sh /data/local/tmp/verify_net.sh
