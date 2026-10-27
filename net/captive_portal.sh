#!/bin/sh
# arkplan · 容器内 captive portal 探测地址（一次性，落在 /data 里，重启/重启容器都保留）
# 为什么要改：Android 13 用 https://www.google.com/generate_204 做连通性验证，
# 本机校园网/代理环境下这个地址连不上（SocketTimeoutException），
# ConnectivityService 就把网络判成 PARTIAL_CONNECTIVITY，部分 App 会自己判“无网”。
# 实测 http/https://connect.rom.miui.com/generate_204 都能返回 204。
# 用法： sudo lxc-attach -P /var/lib/waydroid/lxc -n waydroid -- sh captive_portal.sh
set -u
settings put global captive_portal_mode 1
settings put global captive_portal_use_https 0
settings put global captive_portal_http_url   http://connect.rom.miui.com/generate_204
settings put global captive_portal_https_url  https://connect.rom.miui.com/generate_204
settings put global captive_portal_fallback_url http://connect.rom.miui.com/generate_204
echo "--- now:"
settings list global | grep -i captive
echo "注意：URL 只在 NetworkMonitor 随网络创建时读取，改完要重启容器才生效"
