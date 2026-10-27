#!/bin/bash
set -u
S="lxc-attach -P /var/lib/waydroid/lxc -n waydroid --"
R=/var/lib/waydroid/rootfs

$S logcat -b crash -d > /tmp/crash_before.txt 2>/dev/null
echo "crash log: $(wc -l < /tmp/crash_before.txt) 行"

echo "=== 32 位 .so 统计（/vendor/lib*）==="
: > /tmp/lib32_list.txt
for f in $(find "$R/vendor" -path '*/lib*/*.so' -type f 2>/dev/null); do
  h=$(od -An -tx1 -N5 "$f" 2>/dev/null | tr -d ' \n')
  [ "$h" = "7f454c4601" ] && echo "${f#$R}" >> /tmp/lib32_list.txt
done
wc -l < /tmp/lib32_list.txt
echo "按目录分布:"
sed 's|/[^/]*$||' /tmp/lib32_list.txt | sort | uniq -c | sort -rn

echo "=== boringssl_self_test32 现状 ==="
ls -la "$R/vendor/bin/boringssl_self_test32" 2>/dev/null || echo "  已不存在"
