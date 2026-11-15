#!/bin/bash
# Check a built PHYLAX station image: mounts it read-only and checks what the station needs.
# Fails (exit 1) on any problem. As root:
#
#   sudo build/check-image.sh out/phylax-station-...img.xz
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=config.env
. "$HERE/config.env"
XZ=$(realpath "$1")
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
check() { # check "<what>" <command...>
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then ok "$what"; else bad "$what"; fi
}

xz -dc "$XZ" >"$WORK/image.img"
LOOP=$(losetup -f --show -P -r "$WORK/image.img")
mkdir -p "$WORK/root" "$WORK/boot" "$WORK/data"
mount -o ro "${LOOP}p2" "$WORK/root"
mount -o ro "${LOOP}p1" "$WORK/boot"
mount -o ro "${LOOP}p3" "$WORK/data"
R=$WORK/root
B=$WORK/boot
D=$WORK/data

echo "Partitions"
parted -s "$WORK/image.img" unit MiB print | sed 's/^/  /'
check "data partition labelled $DATA_LABEL" test "$(blkid -s LABEL -o value "${LOOP}p3")" = "$DATA_LABEL"

echo "Boot"
cmd=$(cat "$B/cmdline.txt")
echo "  cmdline.txt: $cmd"
check "no first-boot resize of the system partition" bash -c "! grep -qwE 'resize|init=[^ ]*firstboot' <<<'$cmd'"
check "Wi-Fi country $WIFI_COUNTRY" grep -q "cfg80211.ieee80211_regdom=$WIFI_COUNTRY" "$B/cmdline.txt"
check "phylax-wifi.txt" grep -q '^SSID=$' "$B/phylax-wifi.txt"
check "Wi-Fi on in NetworkManager" bash -c "! grep -q '^WirelessEnabled=false' '$R/var/lib/NetworkManager/NetworkManager.state' 2>/dev/null"
check "Wi-Fi not blocked in the saved radio state" bash -c "! grep -qx 1 '$R'/var/lib/systemd/rfkill/*wlan 2>/dev/null"
check "no Imager/cloud-init user files" bash -c "! ls '$B'/userconf.txt '$B'/user-data 2>/dev/null | grep -q ."

echo "PHYLAX Suite"
check "installed" test -x "$R/opt/phylax-suite/trezor-suite"
check "chrome-sandbox setuid root" bash -c "[ \"\$(stat -c '%U %a' '$R/opt/phylax-suite/chrome-sandbox')\" = 'root 4755' ]"
missing=$(chroot "$R" ldd /opt/phylax-suite/trezor-suite 2>&1 | grep 'not found')
check "all its libraries present" test -z "$missing"
check "udev rules for the blocks (Trezor One USB ids)" grep -qi '534c' "$R/etc/udev/rules.d/51-trezor.rules"
check "start script" test -x "$R/usr/local/bin/phylax-suite"
check "cage" test -x "$R/usr/bin/cage"
check "polkit (Settings > Station may manage Wi-Fi and power)" test -x "$R/usr/lib/polkit-1/polkitd"
check "polkit rule for the kiosk user" grep -q '"phylax"' "$R/etc/polkit-1/rules.d/50-phylax-station.rules"

echo "Services"
for s in graphical.target.wants/phylax-kiosk.service multi-user.target.wants/phylax-grow-data.service \
    multi-user.target.wants/phylax-wifi-setup.service multi-user.target.wants/NetworkManager.service; do
    check "enabled: ${s#*/}" test -L "$R/etc/systemd/system/$s"
done
check "boots to graphical.target" bash -c "readlink '$R/etc/systemd/system/default.target' | grep -q graphical"
for s in userconfig rpi-resize cloud-init-main; do
    check "disabled: $s" bash -c "! ls '$R'/etc/systemd/system/*.wants/$s.service 2>/dev/null | grep -q ."
done
if [ "$DEV_SSH" != 1 ]; then
    check "no SSH server (nothing on the network can log in)" bash -c "! test -e '$R/usr/sbin/sshd'"
    check "no SSH switch file on the boot partition" bash -c "! ls '$B'/ssh '$B'/ssh.txt 2>/dev/null | grep -q ."
fi
if [ "$DEV_SSH" = 1 ]; then
    check "enabled: ssh" test -L "$R/etc/systemd/system/multi-user.target.wants/ssh.service"
    check "no SSH host keys in the image (each station makes its own)" bash -c "! ls '$R'/etc/ssh/ssh_host_* 2>/dev/null | grep -q ."
fi

if [ "$READ_ONLY" = 1 ]; then
    echo "Read-only system"
    check "kernel mounts the system read-only" grep -qw ro "$B/cmdline.txt"
    check "overlay set-up starts before systemd" grep -q 'init=/usr/local/sbin/phylax-overlay-init' "$B/cmdline.txt"
    check "overlay set-up installed" test -x "$R/usr/local/sbin/phylax-overlay-init"
    check "its mount point exists" test -d "$R/phylax-overlay"
    check "boot partition read-only" bash -c "grep -E '/boot/firmware' '$R/etc/fstab' | grep -q 'defaults,ro'"
    if [ "$DEV_SSH" = 1 ]; then
        check "SSH host keys kept on the data partition" test -L "$R/etc/systemd/system/multi-user.target.wants/phylax-ssh-keys.service"
    fi
    check "dev switch phylax-system-rw" test -x "$R/usr/local/sbin/phylax-system-rw"
fi

echo "Users"
shadow_field() { awk -F: -v u="$1" '$1 == u { print $2 }' "$R/etc/shadow"; }
check "$KIOSK_USER: id $KIOSK_UID" bash -c "[ \"\$(awk -F: '\$1 == \"$KIOSK_USER\" {print \$3}' '$R/etc/passwd')\" = $KIOSK_UID ]"
check "$KIOSK_USER: no password login" bash -c "[[ '$(shadow_field "$KIOSK_USER")' == '!'* ]]"
if grep -q '^pi:' "$R/etc/passwd"; then
    check "pi (Raspberry Pi OS placeholder): locked" bash -c "[[ '$(shadow_field pi)' == '!'* || '$(shadow_field pi)' == '*'* ]]"
fi
if [ -n "$DEV_USER" ]; then
    check "$DEV_USER: password set, in sudo" bash -c "[[ '$(shadow_field "$DEV_USER")' == '\$'* ]] && grep -qE '^sudo:.*\b$DEV_USER\b' '$R/etc/group'"
fi

echo "Data partition"
check "fstab: /data, /home/$KIOSK_USER, saved networks" bash -c "grep -q 'LABEL=$DATA_LABEL' '$R/etc/fstab' && grep -q '/home/$KIOSK_USER' '$R/etc/fstab' && grep -q 'system-connections' '$R/etc/fstab'"
check "home/$KIOSK_USER owned by $KIOSK_UID" bash -c "[ \"\$(stat -c %u '$D/home/$KIOSK_USER')\" = $KIOSK_UID ]"
check "network folder private" bash -c "[ \"\$(stat -c %a '$D/network')\" = 700 ]"

echo "Release"
sed 's/^/  /' "$R/etc/phylax-station-release"

[ "$failed" = 0 ] && echo "IMAGE CHECK PASSED" || echo "IMAGE CHECK FAILED"
exit "$failed"
