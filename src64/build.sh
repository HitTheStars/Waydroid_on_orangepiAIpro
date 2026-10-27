#!/bin/bash
# Build the 64-bit (aarch64) audio HAL loader shell for Waydroid.
#
# Host has no Android NDK that runs natively (Google only ships linux-x86_64
# toolchains and this box is aarch64), so we combine:
#   * Ubuntu's native clang-14 / lld-14  (compiler + linker)
#   * the NDK r26d *sysroot* only       (bionic headers, crt objects, libc stubs)
#   * clang-17 runtime from the NDK     (-resource-dir, libclang_rt.builtins)
#   * the device's own libc++.so        (copied to libdev/, so DT_NEEDED is
#                                        libc++.so and std::string uses the exact
#                                        same libc++ ABI as libhidlbase.so)
set -euo pipefail
cd "$(dirname "$0")"

NDK=${NDK:-/home/HwHiAiUser/android-ndk-r26d}
SYS=$NDK/toolchains/llvm/prebuilt/linux-x86_64/sysroot
RES=$NDK/toolchains/llvm/prebuilt/linux-x86_64/lib/clang/17
CXX=${CXX:-/usr/bin/clang++-14}
ROOTFS=${ROOTFS:-/var/lib/waydroid/rootfs}

mkdir -p out libdev
[ -f libdev/libc++.so ] || cp "$ROOTFS/system/lib64/libc++.so" libdev/

$CXX \
    --target=aarch64-linux-android33 \
    --sysroot="$SYS" \
    -isystem "$SYS/usr/include/c++/v1" \
    -resource-dir "$RES" \
    -rtlib=compiler-rt \
    -fPIE -pie -O2 -std=c++17 \
    -fuse-ld=lld \
    -nostdlib++ \
    -Wl,--allow-shlib-undefined \
    -o out/android.hardware.audio.service \
    audio_service_aarch64.cpp \
    libdev/libc++.so \
    -llog -ldl

echo "built: $(pwd)/out/android.hardware.audio.service"
readelf -h out/android.hardware.audio.service | grep -E "类别|Class|系统架构|Machine"
readelf -d out/android.hardware.audio.service | grep NEEDED
