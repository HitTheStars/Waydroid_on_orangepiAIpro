#!/bin/bash
# Install the 64-bit audio HAL loader shell into the vendor overlay and disable
# the three HALs that have no 64-bit implementation in this vendor image.
# Run as root (sudo bash install64.sh). Idempotent.
set -euo pipefail

OVL=/var/lib/waydroid/overlay/vendor
SRC_DIR=$(cd "$(dirname "$0")" && pwd)
BIN="$SRC_DIR/out/android.hardware.audio.service"

if [ ! -f "$BIN" ]; then
    echo "ERROR: $BIN not built" >&2
    exit 1
fi

install -d -m 0755 "$OVL/bin/hw"
install -o 0 -g 2000 -m 0755 "$BIN" "$OVL/bin/hw/android.hardware.audio.service"
echo "installed $OVL/bin/hw/android.hardware.audio.service"

# Drop the HALs that only exist as 32-bit binaries (no AArch32 runtime in this
# arm64_only image). An empty .rc in the overlay's left-most lowerdir shadows
# the original one in vendor.img, so init never spawns them.
install -d -m 0755 "$OVL/etc/init"
for svc in \
    android.hardware.cas@1.2-service \
    android.hardware.media.omx@1.0-service \
    android.hardware.camera.provider@2.7-external-service \
    ; do
    cat > "$OVL/etc/init/$svc.rc" <<EOF
# Disabled: /vendor/bin/hw/$svc is a 32-bit (AArch32) binary and this
# arm64_only image ships no 32-bit bionic/linker, so it can never be exec'd.
# No 64-bit implementation is available in this vendor image; the HAL is not
# required for boot or for Waydroid apps.
EOF
    echo "shadowed $svc.rc"
done

ls -la "$OVL/bin/hw" "$OVL/etc/init"
