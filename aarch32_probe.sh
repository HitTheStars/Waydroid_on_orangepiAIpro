#!/bin/bash
# aarch32_probe.sh —— 一锤定音：本机到底能不能执行 32 位 ARM 程序
#
# 背景：Orange Pi AIpro 20T 的内核 CONFIG_COMPAT=y，但 32 位 ARM ELF 一律 ENOEXEC。
# 原因不是内核没编，是 CPU 没上报 AArch32 EL0 能力，compat_elf_check_arch() 在装载前就拒。
#
# 判据（关键！别搞混）：
#   ENOEXEC / exit 126 "无法执行二进制文件：可执行文件格式错误"
#        -> 装载阶段就被拒 = 内核认为 CPU 不支持 AArch32（硬件门禁）
#   SIGILL
#        -> 装载成功、第一条指令崩 = CPU 不支持但内核以为支持（内核看错）
#   exit 42
#        -> 真支持
#
# 用法：bash arkplan/aarch32_probe.sh

set +e
T=/tmp/aarch32_probe
echo "=== 1. 内核 config 层 ==="
if [ -f /proc/config.gz ]; then
    zcat /proc/config.gz | grep -E "^CONFIG_(COMPAT|BINFMT_ELF)="
else
    echo "/proc/config.gz 不存在"
fi

echo
echo "=== 2. CPU 是否上报 32 位 hwcap ==="
# 若支持 AArch32，Features 里会出现 swp/half/thumb/v26/tls/vfp 之类 32 位特性
FEAT=$(grep -m1 '^Features' /proc/cpuinfo)
echo "$FEAT"
if echo "$FEAT" | grep -qE '\b(swp|half|thumb|vfp|vfpv3|tls)\b'; then
    echo "-> 有 32 位 hwcap，CPU 侧应该支持"
    HW=1
else
    echo "-> 没有任何 32 位 hwcap，CPU 侧判定不支持 AArch32"
    HW=0
fi

echo
echo "=== 3. 实测最小静态 32 位 ELF（3 条指令, mov r7,#1 / mov r0,#42 / svc 0）==="
python3 - "$T" <<'PY'
import struct, sys, os
out = sys.argv[1]
EHSIZE, PHENTSIZE, base = 52, 32, 0x10000
code_off = EHSIZE + PHENTSIZE
code = bytes([0x01,0x70,0xA0,0xE3, 0x2A,0x00,0xA0,0xE3, 0x00,0x00,0x00,0xEF])
total = code_off + len(code)
ident = b'\x7fELF' + bytes([1,1,1,0]) + b'\x00'*8
ehdr = ident + struct.pack('<HHIIIIIHHHHHH', 2, 40, 1, base+code_off, EHSIZE, 0,
                           0x05000000, EHSIZE, PHENTSIZE, 1, 40, 0, 0)
phdr = struct.pack('<IIIIIIII', 1, 0, base, base, total, total, 5, 0x1000)
open(out,'wb').write(ehdr+phdr+code)
os.chmod(out, 0o755)
PY

"$T" 2>/tmp/aarch32_err
RC=$?
ERR=$(cat /tmp/aarch32_err)

if [ $RC -eq 42 ]; then
    echo "-> exit 42：★本机支持 32 位 ARM★"
    VERDICT=OK
elif [ $RC -eq 126 ] || echo "$ERR" | grep -qiE "format|格式"; then
    echo "-> $ERR"
    echo "-> ENOEXEC：内核在装载阶段就拒绝了 32 位 ELF"
    VERDICT=GATE
elif [ $RC -ge 128 ]; then
    echo "-> 被信号杀死 (rc=$RC)，可能是 SIGILL = 内核以为支持但 CPU 不支持"
    VERDICT=ILL
else
    echo "-> rc=$RC（非预期）"
    VERDICT=UNKNOWN
fi

echo
echo "================ 结论 ================"
case $VERDICT in
  OK)   echo "支持 32 位。可继续用带 32 位 HAL 的 vendor。" ;;
  GATE) echo "不支持 32 位（CONFIG_COMPAT=y 但 CPU 未上报 AArch32 EL0）。"
        echo "→ vendor 必须纯 64 位；任何 32 位 HAL/服务都起不来，补 linker 无用。"
        echo "→ 不要再去折腾 CONFIG_COMPAT 或重编内核，门是 CPU 关的。" ;;
  ILL)  echo "内核与硬件认知不一致，需查 ID_AA64PFR0_EL1。" ;;
  *)    echo "无法定论，手工看上面输出。" ;;
esac
echo "hwcap32=$HW verdict=$VERDICT"
