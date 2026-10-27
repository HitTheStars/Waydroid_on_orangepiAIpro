#!/bin/bash
# arkplan · Waydroid 容器出网修复（宿主机侧，幂等）
#
# 背景（2026-10-28 实测）：
#   本机 ufw 处于启用状态，且 DEFAULT_FORWARD_POLICY="DROP"，
#   于是 nft 的 FORWARD 链策略是 DROP；而 waydroid-net.sh 显式优先用
#   iptables-legacy（见脚本里 IPTABLES_BIN="$(command -v iptables-legacy)"），
#   waydroid0 的 ACCEPT 规则只落在 legacy 表里，管不到 nft 的那条 DROP 策略。
#   结果：容器 → 外网被丢包。同时 ufw 默认 deny incoming，
#   容器发出的 DHCPDISCOVER(udp/67) 也被 INPUT 丢，dnsmasq 的 OFFER 回不去，
#   容器拿不到默认路由和 DNS（netd 的 eth0 表里只有 192.168.240.0/24）。
#
# 需要 root。重复执行安全（ufw 会跳过已存在规则）。
set -u

echo "== 1. 转发开关 =="
sysctl -w net.ipv4.ip_forward=1
printf 'net.ipv4.ip_forward=1\n' > /etc/sysctl.d/99-ark-waydroid.conf
echo "written /etc/sysctl.d/99-ark-waydroid.conf"

echo "== 2. ufw：waydroid0 入站 DHCP / DNS =="
ufw allow in on waydroid0 to any port 67 proto udp
ufw allow in on waydroid0 to any port 53 proto udp
ufw allow in on waydroid0 to any port 53 proto tcp

echo "== 3. ufw：waydroid0 双向 FORWARD（这是出网的关键）=="
ufw route allow in on waydroid0
ufw route allow out on waydroid0

echo "== 4. 校验 =="
echo "-- ufw 规则（应看到 waydroid0 的 4 条 + 2 条 FWD）"
ufw status numbered | grep -i waydroid0
echo "-- nft(默认) FORWARD 链里的 waydroid0 ACCEPT"
iptables -S ufw-user-forward | grep waydroid0
echo "-- legacy 表里 waydroid-net.sh 加的 NAT（waydroid 自己维护，缺了就是没跑过 waydroid-net.sh）"
iptables-legacy -t nat -S POSTROUTING | grep 192.168.240.0
echo "== done =="
