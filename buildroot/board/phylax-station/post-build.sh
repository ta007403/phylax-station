#!/bin/sh
# PHYLAX station (Buildroot image): last touches to the system before it is packed.
#
# Environment: PHYLAX_SUITE_DIR (PHYLAX Suite's Linux arm64 AppImage, extracted: see
# buildroot/README.md), PHYLAX_SUITE_VERSION, PHYLAX_IMAGE_VERSION, PHYLAX_IMAGE_KIND.
set -eu

REPO="$(dirname "$BR2_EXTERNAL_PHYLAX_PATH")"

# PHYLAX Suite, as in the Raspberry Pi OS image (build/build-image.sh)
: "${PHYLAX_SUITE_DIR:?PHYLAX_SUITE_DIR: PHYLAX Suite's extracted AppImage}"
[ -x "$PHYLAX_SUITE_DIR/trezor-suite" ] || { echo "No trezor-suite in $PHYLAX_SUITE_DIR" >&2; exit 1; }
rm -rf "${TARGET_DIR}/opt/phylax-suite"
mkdir -p "${TARGET_DIR}/opt"
cp -a "$PHYLAX_SUITE_DIR" "${TARGET_DIR}/opt/phylax-suite"
chmod 755 "${TARGET_DIR}/opt/phylax-suite"
# Chromium's sandbox helper must be setuid root (the files are owned by root in the image)
chmod 4755 "${TARGET_DIR}/opt/phylax-suite/chrome-sandbox"
install -D -m 0755 "$REPO/rootfs/usr/local/bin/phylax-suite" "${TARGET_DIR}/usr/local/bin/phylax-suite"
# the PHYLAX blocks on USB: Suite's own udev rules (Trezor One USB ids)
install -D -m 0644 "${TARGET_DIR}/opt/phylax-suite/resources/bin/udev/51-trezor.rules" \
    "${TARGET_DIR}/etc/udev/rules.d/51-trezor.rules"

# every library PHYLAX Suite's program needs must be in the image (Buildroot builds only what the
# defconfig lists): its NEEDED entries, found in the system or next to it
missing=0
for elf in "${TARGET_DIR}/opt/phylax-suite/trezor-suite" "${TARGET_DIR}"/opt/phylax-suite/*.so*; do
    [ -f "$elf" ] || continue
    for lib in $(readelf -d "$elf" | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p'); do
        found=0
        for dir in usr/lib lib opt/phylax-suite; do
            # -L too: the system's library links point to absolute paths inside the image
            if [ -e "${TARGET_DIR}/$dir/$lib" ] || [ -L "${TARGET_DIR}/$dir/$lib" ]; then found=1; fi
        done
        if [ "$found" = 0 ]; then
            echo "PHYLAX Suite: $(basename "$elf") needs $lib, not in the image" >&2
            missing=1
        fi
    done
done
[ "$missing" = 0 ] || exit 1
echo "PHYLAX Suite: every library it needs is in the image"
# the keyboard layouts cage and Suite load (libxkbcommon)
[ -f "${TARGET_DIR}/usr/share/X11/xkb/rules/evdev" ] || { echo "No keyboard layouts (/usr/share/X11/xkb)" >&2; exit 1; }

# the kiosk at start; the start goes on to the graphical target
mkdir -p "${TARGET_DIR}/etc/systemd/system/graphical.target.wants"
ln -sf /etc/systemd/system/phylax-kiosk.service \
    "${TARGET_DIR}/etc/systemd/system/graphical.target.wants/phylax-kiosk.service"
ln -sf /usr/lib/systemd/system/graphical.target "${TARGET_DIR}/etc/systemd/system/default.target"

# station marker and versions (PHYLAX Suite's Settings > Station reads this file)
BR_VERSION=$(sed -n 's/^BUILDROOT_TAG=//p' "${BR2_EXTERNAL_PHYLAX_PATH}/buildroot.version")
cat > "${TARGET_DIR}/etc/phylax-station-release" <<REL
IMAGE_VERSION=${PHYLAX_IMAGE_VERSION:-local}
IMAGE_KIND=${PHYLAX_IMAGE_KIND:-dev}
SUITE_VERSION=${PHYLAX_SUITE_VERSION:-unknown}
BASE=Buildroot ${BR_VERSION}
REL
