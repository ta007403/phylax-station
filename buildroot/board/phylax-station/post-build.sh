#!/bin/sh
# PHYLAX station (Buildroot image): last touches to the system before it is packed.
#
# Environment: PHYLAX_IMAGE_KIND (dev or production), PHYLAX_SUITE_DIR (PHYLAX Suite's Linux arm64
# AppImage, extracted: see buildroot/README.md), PHYLAX_SUITE_VERSION, PHYLAX_IMAGE_VERSION.
set -eu

case "${PHYLAX_IMAGE_KIND:-}" in
    dev | production) ;;
    *) echo "PHYLAX_IMAGE_KIND must be dev or production" >&2; exit 1 ;;
esac

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

# CUPS: PHYLAX Suite (Electron) is linked with its library (libcups) only. No print server, its
# network listeners (cups-lpd: port 515) and tools: removed, so nothing can start them.
rm -f "${TARGET_DIR}"/usr/lib/systemd/system/cups* "${TARGET_DIR}"/etc/systemd/system/*/cups* \
    "${TARGET_DIR}"/usr/lib/udev/rules.d/70-usb-printers.rules
rm -rf "${TARGET_DIR}/usr/lib/cups" "${TARGET_DIR}/etc/cups" "${TARGET_DIR}/usr/share/cups"
for f in sbin/cupsd sbin/cupsfilter sbin/cupsctl sbin/cupsaccept sbin/cupsreject sbin/cupsenable \
    sbin/cupsdisable sbin/lpadmin sbin/lpinfo sbin/lpmove sbin/lpc bin/lp bin/lpr bin/lpq bin/lprm \
    bin/lpstat bin/cancel bin/lpoptions bin/cupstestppd bin/ipptool bin/ippfind bin/ippeveprinter; do
    rm -f "${TARGET_DIR}/usr/$f"
done
if ls "${TARGET_DIR}"/usr/lib/systemd/system/cups* "${TARGET_DIR}/usr/sbin/cupsd" >/dev/null 2>&1; then
    echo "CUPS print server still in the image" >&2
    exit 1
fi

# The station's files shared with the Raspberry Pi OS image (the repo's rootfs/): Wi-Fi from
# phylax-wifi.txt, the start-up sound, who may manage Wi-Fi and shut down (polkit), the kiosk; the
# read-only system with the data partition (phylax-overlay-init, phylax-grow-data, phylax-system-rw)
for f in usr/local/sbin/phylax-wifi-setup usr/local/sbin/phylax-startup-sound \
    usr/local/sbin/phylax-overlay-init usr/local/sbin/phylax-grow-data usr/local/sbin/phylax-system-rw; do
    install -D -m 0755 "$REPO/rootfs/$f" "${TARGET_DIR}/$f"
done
for f in etc/systemd/system/phylax-wifi-setup.service etc/systemd/system/phylax-startup-sound.service \
    etc/systemd/system/phylax-kiosk.service etc/systemd/system/phylax-grow-data.service \
    etc/polkit-1/rules.d/50-phylax-station.rules usr/share/phylax/startup.wav; do
    install -D -m 0644 "$REPO/rootfs/$f" "${TARGET_DIR}/$f"
done

# The partitions, as on the Raspberry Pi OS image: the boot partition (phylax-wifi.txt) read-only
# (written only by phylax-wifi-setup and phylax-system-rw); the data partition (made by
# post-image.sh) with the kiosk user's home (PHYLAX Suite's data) and the saved networks. The
# system partition is read-only through phylax-overlay-init (cmdline.txt), its RAM layer's mount
# point /phylax-overlay.
mkdir -p "${TARGET_DIR}/boot/firmware" "${TARGET_DIR}/data" "${TARGET_DIR}/phylax-overlay"
sed -i '/# PHYLAX station partitions/,$d' "${TARGET_DIR}/etc/fstab"
cat >>"${TARGET_DIR}/etc/fstab" <<'FSTAB'
# PHYLAX station partitions
PARTUUID=50485958-01  /boot/firmware  vfat  defaults,ro,noatime  0  2
LABEL=PHYLAXDATA  /data  ext4  defaults,noatime  0  2
/data/home/phylax  /home/phylax  none  bind,x-systemd.requires-mounts-for=/data  0  0
/data/network  /etc/NetworkManager/system-connections  none  bind,x-systemd.requires-mounts-for=/data  0  0
FSTAB

# The services at start; the start goes on to the graphical target (the kiosk)
systemctl_target() { "${HOST_DIR}/bin/systemctl" --root="${TARGET_DIR}" "$@"; }
systemctl_target enable phylax-kiosk.service phylax-startup-sound.service phylax-grow-data.service \
    phylax-wifi-setup.service NetworkManager.service systemd-timesyncd.service
systemctl_target set-default graphical.target

# Production: no login of any kind, as the Raspberry Pi OS image's production image (root and the
# kiosk user are locked; there is no other user)
rm -f "${TARGET_DIR}/etc/sysctl.d/90-phylax-station.conf"
if [ "$PHYLAX_IMAGE_KIND" = production ]; then
    # no text consoles: no login prompt on Ctrl+Alt+F2-F6 nor on the serial port
    systemctl_target mask getty@.service autovt@.service serial-getty@.service console-getty.service
    # PHYLAX Suite's kiosk: no switching away to a console
    sed -i 's#/usr/bin/cage -s -- #/usr/bin/cage -- #' "${TARGET_DIR}/etc/systemd/system/phylax-kiosk.service"
    grep -q 'ExecStart=/usr/bin/cage -- ' "${TARGET_DIR}/etc/systemd/system/phylax-kiosk.service"
    # no "magic SysRq" keyboard shortcuts (kill processes, reboot, ...)
    mkdir -p "${TARGET_DIR}/etc/sysctl.d"
    echo "kernel.sysrq = 0" >"${TARGET_DIR}/etc/sysctl.d/90-phylax-station.conf"
fi

# station marker and versions (PHYLAX Suite's Settings > Station reads this file)
BR_VERSION=$(sed -n 's/^BUILDROOT_TAG=//p' "${BR2_EXTERNAL_PHYLAX_PATH}/buildroot.version")
cat > "${TARGET_DIR}/etc/phylax-station-release" <<REL
IMAGE_VERSION=${PHYLAX_IMAGE_VERSION:-local}
IMAGE_KIND=${PHYLAX_IMAGE_KIND}
SUITE_VERSION=${PHYLAX_SUITE_VERSION:-unknown}
BASE=Buildroot ${BR_VERSION}
REL
