#!/bin/bash
# 方舟计划 · 分步加载探针
# 每一代加载只做一件事，崩了靠 ARKSTEP 标记定位。
# 用法: sudo ./load_step.sh 1|2|3|4|5

set -u
BASE="$(cd "$(dirname "$0")" && pwd)"
MOD_BINDER="$BASE/src/binder-mod"
MOD_ASHMEM="$BASE/src/ashmem-mod"
MARK_TAG="ARKSTEP"

mark() {
    local tag="ARKSTEP-$1"
    echo "$tag $(date -Is)" > /dev/kmsg 2>/dev/null
    logger -t "$MARK_TAG" "BEFORE $1"
    sync
    echo "[mark] $tag"
}

check_alive() {
    local tag="ARKSTEP-$1-OK"
    echo "$tag" > /dev/kmsg 2>/dev/null
    logger -t "$MARK_TAG" "AFTER $1 OK"
    sync
    echo "[mark] $tag"
}

case "${1:-}" in
1)
    mark "01-load-binder"
    insmod "$MOD_BINDER/binder_linux.ko" || { echo "insmod 失败"; exit 1; }
    check_alive "01-load-binder"
    lsmod | grep binder
    echo "--- 观察 10 秒，若无异常继续 ---"
    dmesg | tail -5
    ;;
2)
    mark "02-open-binder"
    # 只 open + BINDER_VERSION，不 mmap（mmap 后裸读必 SIGBUS，是我上次写错）
    python3 - <<'EOF'
import os, fcntl, struct
BINDER_VERSION = 0xC0046209
for p in ('/dev/binder','/dev/hwbinder','/dev/vndbinder'):
    try:
        fd = os.open(p, os.O_RDWR)
        buf = struct.pack('i', 0)
        ver = struct.unpack('i', fcntl.ioctl(fd, BINDER_VERSION, buf))[0]
        os.close(fd)
        print(f'{p}: OPEN OK ver={ver}')
    except Exception as e:
        print(f'{p}: FAIL {e}')
EOF
    check_alive "02-open-binder"
    ;;
3)
    mark "03-mount-binderfs"
    mkdir -p /dev/binderfs
    mount -t binder binder /dev/binderfs || { echo "mount 失败"; exit 1; }
    ls -l /dev/binderfs/
    check_alive "03-mount-binderfs"
    echo "--- 到这里停下，别 open 动态节点，先观察 ---"
    ;;
4)
    mark "04-open-binderfs"
    python3 - <<'EOF'
import os, fcntl, struct
BINDER_VERSION = 0xC0046209
for p in ('/dev/binderfs/binder','/dev/binderfs/hwbinder','/dev/binderfs/vndbinder'):
    try:
        fd = os.open(p, os.O_RDWR)
        buf = struct.pack('i', 0)
        ver = struct.unpack('i', fcntl.ioctl(fd, BINDER_VERSION, buf))[0]
        os.close(fd)
        print(f'{p}: OPEN OK ver={ver}')
    except Exception as e:
        print(f'{p}: FAIL {e}')
EOF
    check_alive "04-open-binderfs"
    ;;
5)
    mark "05-load-ashmem"
    insmod "$MOD_ASHMEM/ashmem_mod.ko" || { echo "insmod 失败"; exit 1; }
    check_alive "05-load-ashmem"
    lsmod | grep -i ashmem
    echo "--- 观察 30 秒，注意风扇 ---"
    ;;
*)
    echo "用法: sudo $0 {1|2|3|4|5}"
    echo "  1 = 只加载 binder_linux.ko"
    echo "  2 = 只 open 静态 /dev/binder*（不 mmap）"
    echo "  3 = 只挂 binderfs，不 open 动态节点"
    echo "  4 = open binderfs 动态节点"
    echo "  5 = 加载 ashmem_mod.ko"
    exit 1
    ;;
esac
