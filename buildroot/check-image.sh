#!/bin/bash
# Check a built PHYLAX station Buildroot image: mounts it read-only and checks what the station
# needs (as build/check-image.sh does for the Raspberry Pi OS image). Fails (exit 1) on any
# problem. As root:
#
#   sudo buildroot/check-image.sh <image .img or .img.xz> dev|production
set -uo pipefail

IMAGE=$(realpath "$1")
KIND=$2
DATA_LABEL=PHYLAXDATA
KIOSK_USER=phylax
KIOSK_UID=1100
WIFI_COUNTRY=TH
WORK=$(mktemp -d /tmp/phylax-check.XXXXXX)
LOOP=""
cleanup() {
    for m in boot data root; do mountpoint -q "$WORK/$m" && umount "$WORK/$m"; done
    [ -n "$LOOP" ] && losetup -d "$LOOP"
    rm -rf "$WORK"
}
trap cleanup EXIT

failed=0
ok() { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; failed=1; }
# a program in the image (Buildroot merges /bin, /sbin into /usr)
have() {
    local d
    for d in usr/bin usr/sbin bin sbin; do [ -x "$R/$d/$1" ] && return 0; done
    return 1
}
export -f have
check() { # check "<what>" <command...>
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then ok "$what"; else bad "$what"; fi
}

case "$IMAGE" in
    *.xz) xz -dc "$IMAGE" >"$WORK/image.img" ;;
    *) cp "$IMAGE" "$WORK/image.img" ;;
esac
LOOP=$(losetup -f --show -P -r "$WORK/image.img")
mkdir -p "$WORK/root" "$WORK/boot" "$WORK/data"
mount -o ro "${LOOP}p2" "$WORK/root"
mount -o ro "${LOOP}p1" "$WORK/boot"
mount -o ro "${LOOP}p3" "$WORK/data"
export R=$WORK/root
B=$WORK/boot
D=$WORK/data

echo "Partitions"
sfdisk -l "$WORK/image.img" | sed 's/^/  /'
check "disk id 50485958 (cmdline.txt finds the system by it)" bash -c "sfdisk --disk-id '$WORK/image.img' | grep -qix 0x50485958"
check "data partition labelled $DATA_LABEL" test "$(blkid -s LABEL -o value "${LOOP}p3")" = "$DATA_LABEL"

echo "Boot"
cmd=$(cat "$B/cmdline.txt")
echo "  cmdline.txt: $cmd"
check "system partition by PARTUUID" grep -q 'root=PARTUUID=50485958-02' "$B/cmdline.txt"
check "Wi-Fi country $WIFI_COUNTRY" grep -q "cfg80211.ieee80211_regdom=$WIFI_COUNTRY" "$B/cmdline.txt"
check "phylax-wifi.txt" grep -q '^SSID=$' "$B/phylax-wifi.txt"
check "kernel and config.txt" bash -c "test -s '$B/Image' && grep -qx 'kernel=Image' '$B/config.txt'"
check "CM5 device tree" test -s "$B/bcm2712-rpi-cm5-cm5io.dtb"

echo "PHYLAX Suite"
check "installed" test -x "$R/opt/phylax-suite/trezor-suite"
check "chrome-sandbox setuid root" bash -c "[ \"\$(stat -c '%u %a' '$R/opt/phylax-suite/chrome-sandbox')\" = '0 4755' ]"
missing=""
for lib in $(readelf -d "$R/opt/phylax-suite/trezor-suite" | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p'); do
    found=0
    for dir in usr/lib lib opt/phylax-suite; do
        if [ -e "$R/$dir/$lib" ] || [ -L "$R/$dir/$lib" ]; then found=1; fi
    done
    [ "$found" = 1 ] || missing="$missing $lib"
done
check "all its libraries present${missing:+ (missing:$missing)}" test -z "$missing"
check "keyboard layouts (xkb)" test -f "$R/usr/share/X11/xkb/rules/evdev"
check "udev rules for the blocks (Trezor One USB ids)" grep -qi '534c' "$R/etc/udev/rules.d/51-trezor.rules"
check "start script" test -x "$R/usr/local/bin/phylax-suite"
check "cage" have cage
check "polkit (Settings > Station may manage Wi-Fi and power)" test -x "$R/usr/lib/polkit-1/polkitd"
check "polkit rule for the kiosk user" grep -q '"phylax"' "$R/etc/polkit-1/rules.d/50-phylax-station.rules"
check "nmcli" have nmcli
check "Wi-Fi firmware for the CM5" test -e "$R/lib/firmware/brcm/brcmfmac43455-sdio.raspberrypi,5-compute-module.bin"

echo "Start-up sound"
check "speaker amp in config.txt (dtoverlay=max98357a)" grep -qx 'dtoverlay=max98357a' "$B/config.txt"
check "the sound" test -s "$R/usr/share/phylax/startup.wav"
check "aplay" have aplay
check "enabled: phylax-startup-sound (early, sysinit)" test -L "$R/etc/systemd/system/sysinit.target.wants/phylax-startup-sound.service"

echo "Services"
for s in graphical.target.wants/phylax-kiosk.service multi-user.target.wants/phylax-grow-data.service \
    multi-user.target.wants/phylax-wifi-setup.service multi-user.target.wants/NetworkManager.service; do
    check "enabled: ${s#*/}" test -L "$R/etc/systemd/system/$s"
done
check "boots to graphical.target" bash -c "readlink '$R/etc/systemd/system/default.target' | grep -q graphical"
check "no SSH server (nothing on the network can log in)" bash -c '! have sshd && ! have dropbear'
check "no print server (CUPS)" bash -c '! have cupsd && ! ls "$R"/usr/lib/systemd/system/cups* 2>/dev/null | grep -q .'
check "no LLMNR / multicast DNS" bash -c "grep -qx 'LLMNR=no' '$R/etc/systemd/resolved.conf.d/phylax-station.conf' && grep -qx 'MulticastDNS=no' '$R/etc/systemd/resolved.conf.d/phylax-station.conf'"

echo "Read-only system"
check "kernel mounts the system read-only" grep -qw ro "$B/cmdline.txt"
check "overlay set-up starts before systemd" grep -q 'init=/usr/local/sbin/phylax-overlay-init' "$B/cmdline.txt"
check "overlay set-up installed" test -x "$R/usr/local/sbin/phylax-overlay-init"
check "its mount point exists" test -d "$R/phylax-overlay"
check "the overlay kernel module" bash -c "ls '$R'/lib/modules/*/kernel/fs/overlayfs/overlay.ko* >/dev/null 2>&1 || grep -qw overlay '$R'/lib/modules/*/modules.builtin"
check "boot partition read-only" bash -c "grep -E '/boot/firmware' '$R/etc/fstab' | grep -q 'defaults,ro'"
check "dev switch phylax-system-rw" test -x "$R/usr/local/sbin/phylax-system-rw"

echo "Users"
shadow_field() { awk -F: -v u="$1" '$1 == u { print $2 }' "$R/etc/shadow"; }
check "$KIOSK_USER: id $KIOSK_UID" bash -c "[ \"\$(awk -F: '\$1 == \"$KIOSK_USER\" {print \$3}' '$R/etc/passwd')\" = $KIOSK_UID ]"
check "$KIOSK_USER: no password login" bash -c "[[ '$(shadow_field "$KIOSK_USER")' == '!'* || '$(shadow_field "$KIOSK_USER")' == '*'* ]]"
check "root: no password login" bash -c "[[ '$(shadow_field root)' == '!'* || '$(shadow_field root)' == '*'* ]]"
if [ "$KIND" = dev ]; then
    check "admin: password set, in sudo" bash -c "[[ '$(shadow_field admin)' == '\$'* ]] && grep -qE '^sudo:.*\badmin\b' '$R/etc/group'"
fi

if [ "$KIND" = production ]; then
    echo "Production: no way in"
    # a usable password hash starts with "$"; "!"/"*" = locked; empty = no password at all
    open_accounts=$(awk -F: '$2 == "" || $2 ~ /^\$/ { print $1 }' "$R/etc/shadow" | tr '\n' ' ')
    check "no account can log in${open_accounts:+ (open: $open_accounts)}" test -z "$open_accounts"
    check "no admin user" bash -c "! grep -q '^admin:' '$R/etc/passwd'"
    check "no sudo" bash -c '! have sudo'
    for unit in getty@.service autovt@.service serial-getty@.service console-getty.service; do
        check "masked: $unit" bash -c "[ \"\$(readlink '$R/etc/systemd/system/$unit')\" = /dev/null ]"
    done
    check "kiosk without console switching (cage without -s)" grep -q 'ExecStart=/usr/bin/cage -- ' "$R/etc/systemd/system/phylax-kiosk.service"
    check "no serial console on the boot line" bash -c "! grep -q 'console=ttyAMA' '$B/cmdline.txt'"
    check "magic SysRq keys off" grep -qx 'kernel.sysrq = 0' "$R/etc/sysctl.d/90-phylax-station.conf"
    check "release says production" grep -qx 'IMAGE_KIND=production' "$R/etc/phylax-station-release"
else
    check "release says dev" grep -qx 'IMAGE_KIND=dev' "$R/etc/phylax-station-release"
fi

echo "Data partition"
check "fstab: /data, /home/$KIOSK_USER, saved networks" bash -c "grep -q 'LABEL=$DATA_LABEL' '$R/etc/fstab' && grep -q '/home/$KIOSK_USER' '$R/etc/fstab' && grep -q 'system-connections' '$R/etc/fstab'"
check "home/$KIOSK_USER owned by $KIOSK_UID" bash -c "[ \"\$(stat -c %u '$D/home/$KIOSK_USER')\" = $KIOSK_UID ]"
check "network folder private" bash -c "[ \"\$(stat -c %a '$D/network')\" = 700 ]"
check "grows at the first start (findmnt, lsblk, sfdisk, partx, resize2fs)" bash -c 'test -x "$R/usr/local/sbin/phylax-grow-data" && have findmnt && have lsblk && have sfdisk && have partx && have resize2fs'

echo "Release"
sed 's/^/  /' "$R/etc/phylax-station-release"

[ "$failed" = 0 ] && echo "IMAGE CHECK PASSED" || echo "IMAGE CHECK FAILED"
exit "$failed"
