#!/bin/bash
# Build the PHYLAX station eMMC image: official Raspberry Pi OS Lite 64-bit, plus PHYLAX Suite
# in a kiosk, plus a data partition. Runs as root on an arm64 Linux machine (GitHub's
# ubuntu-24.04-arm runner): the image's programs run natively in a chroot, no emulation.
#
#   sudo build/build-image.sh <PHYLAX-Suite-linux-arm64.AppImage> <out-dir>
#
# Output: <out-dir>/phylax-station-<version>.img.xz, its .sha256 and build-info.txt.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(dirname "$HERE")
APPIMAGE=$(realpath "$1")
OUT=$(realpath -m "$2")
# shellcheck source=config.env
. "$HERE/config.env"

[ "$(id -u)" = 0 ] || { echo "Run as root." >&2; exit 1; }
[ "$(uname -m)" = aarch64 ] || { echo "Run on arm64 (aarch64)." >&2; exit 1; }
[ -f "$APPIMAGE" ] || { echo "AppImage not found: $APPIMAGE" >&2; exit 1; }

WORK=$(mktemp -d /tmp/phylax-station.XXXXXX)
ROOT=$WORK/root
LOOP=""
cleanup() {
    set +e
    for m in boot/firmware dev/pts dev proc sys run data; do
        mountpoint -q "$ROOT/$m" && umount -l "$ROOT/$m"
    done
    mountpoint -q "$ROOT" && umount -l "$ROOT"
    mountpoint -q "$WORK/data" && umount -l "$WORK/data"
    [ -n "$LOOP" ] && losetup -d "$LOOP"
    rm -rf "$WORK"
}
trap cleanup EXIT

log() { printf '\n=== %s\n' "$*"; }

log "Raspberry Pi OS Lite 64-bit: download and check"
url=$(curl -fsSL -o /dev/null -w '%{url_effective}' "$PI_OS_URL")
echo "$url"
curl -fsSL --retry 3 -o "$WORK/base.img.xz" "$url"
expected=$(curl -fsSL --retry 3 "$url.sha256" | awk '{print $1}')
echo "$expected  $WORK/base.img.xz" | sha256sum -c -
base_name=$(basename "$url" .img.xz)
xz -d -T0 "$WORK/base.img.xz"
IMG=$WORK/base.img

log "Partitions: system +${ROOT_GROW_MB} MB, data partition ${DATA_MB} MB"
truncate -s +"$((ROOT_GROW_MB + DATA_MB))M" "$IMG"
parted -s "$IMG" unit MiB print
p2_end=$(parted -s -m "$IMG" unit MiB print | awk -F: '$1 == "2" { sub("MiB", "", $3); print int($3) }')
new_p2_end=$((p2_end + ROOT_GROW_MB))
parted -s "$IMG" resizepart 2 "${new_p2_end}MiB"
parted -s "$IMG" mkpart primary ext4 "${new_p2_end}MiB" 100%
parted -s "$IMG" unit MiB print
LOOP=$(losetup -f --show -P "$IMG")
e2fsck -fy "${LOOP}p2" || [ $? -le 1 ]
resize2fs "${LOOP}p2"
mkfs.ext4 -q -L "$DATA_LABEL" "${LOOP}p3"

log "Mount"
mkdir -p "$ROOT"
mount "${LOOP}p2" "$ROOT"
mount "${LOOP}p1" "$ROOT/boot/firmware"
for m in dev dev/pts proc sys run; do mount --bind "/$m" "$ROOT/$m"; done
cp /etc/resolv.conf "$WORK/resolv.conf.host"
mv "$ROOT/etc/resolv.conf" "$WORK/resolv.conf.image" 2>/dev/null || true
cp /etc/resolv.conf "$ROOT/etc/resolv.conf"
# no service starts inside the chroot
printf '#!/bin/sh\nexit 101\n' >"$ROOT/usr/sbin/policy-rc.d"
chmod 755 "$ROOT/usr/sbin/policy-rc.d"

log "The base image as it comes (first-boot setup to take over)"
echo "cmdline.txt: $(cat "$ROOT/boot/firmware/cmdline.txt")"
grep -v '^#' "$ROOT/etc/fstab"
cat "$ROOT/etc/os-release" | grep -E '^(PRETTY_NAME|VERSION_CODENAME)='
chroot "$ROOT" systemctl list-unit-files --state=enabled --no-pager | grep -iE 'resize|firstboot|userconf|cloud|rpi|ssh|regenerate' || true

in_root() { chroot "$ROOT" /usr/bin/env DEBIAN_FRONTEND=noninteractive LC_ALL=C "$@"; }

log "Packages: kiosk (cage), PHYLAX Suite's libraries, tools"
in_root apt-get update -q
# Electron's libraries; Debian 13 renamed some (t64): take whichever exists.
pkgs="cage network-manager cloud-guest-utils iw rfkill fonts-dejavu-core libnss3 libgbm1 libxss1
      libsecret-1-0 libnotify4 libuuid1 xdg-utils libdrm2 libxkbcommon0 libxshmfence1"
for alt in "libgtk-3-0t64 libgtk-3-0" "libasound2t64 libasound2" "libatspi2.0-0t64 libatspi2.0-0" \
    "libatk-bridge2.0-0t64 libatk-bridge2.0-0" "libcups2t64 libcups2"; do
    for p in $alt; do
        if in_root apt-cache show "$p" >/dev/null 2>&1; then pkgs="$pkgs $p"; break; fi
    done
done
# shellcheck disable=SC2086
in_root apt-get install -y -q --no-install-recommends $pkgs
[ "$DEV_SSH" = 1 ] && in_root apt-get install -y -q --no-install-recommends openssh-server
in_root apt-get clean

log "PHYLAX Suite"
(cd "$WORK" && "$APPIMAGE" --appimage-extract >/dev/null)
rm -rf "$ROOT/opt/phylax-suite"
mv "$WORK/squashfs-root" "$ROOT/opt/phylax-suite"
chown -R root:root "$ROOT/opt/phylax-suite"
chmod 755 "$ROOT/opt/phylax-suite"
# Chromium's sandbox helper must be setuid root
chmod 4755 "$ROOT/opt/phylax-suite/chrome-sandbox"
missing=$(in_root ldd /opt/phylax-suite/trezor-suite | grep 'not found' || true)
[ -z "$missing" ] || { echo "PHYLAX Suite misses libraries:"; echo "$missing"; exit 1; }
# the PHYLAX blocks on USB: Suite's own udev rules (Trezor One USB ids)
cp "$ROOT/opt/phylax-suite/resources/bin/udev/51-trezor.rules" "$ROOT/etc/udev/rules.d/51-trezor.rules"
suite_version=$(basename "$APPIMAGE" | sed -E 's/^PHYLAX-Suite-(.*)-linux-arm64\.AppImage$/\1/')

log "Users"
echo "accounts in the base image:"; awk -F: '$3 >= 1000 && $3 < 65000 {print "  " $1 " " $3}' "$ROOT/etc/passwd"
in_root groupadd -f plugdev
in_root useradd -m -u "$KIOSK_UID" -s /bin/bash -G plugdev,video,render,input,audio "$KIOSK_USER"
in_root passwd -l "$KIOSK_USER"
# Raspberry Pi OS's placeholder account (its first-boot wizard renames it): unused here, locked
if grep -q '^pi:' "$ROOT/etc/passwd"; then
    in_root usermod -L -s /usr/sbin/nologin pi
fi
if [ -n "$DEV_USER" ]; then
    in_root useradd -m -s /bin/bash -G sudo,adm,plugdev,netdev,video "$DEV_USER"
    echo "$DEV_USER:$DEV_PASSWORD" | in_root chpasswd
fi

log "System settings"
echo "$HOSTNAME" >"$ROOT/etc/hostname"
sed -i -E "s/^127\.0\.1\.1.*/127.0.1.1\t$HOSTNAME/" "$ROOT/etc/hosts"
grep -q '^127\.0\.1\.1' "$ROOT/etc/hosts" || printf '127.0.1.1\t%s\n' "$HOSTNAME" >>"$ROOT/etc/hosts"
ln -sf "/usr/share/zoneinfo/$TIMEZONE" "$ROOT/etc/localtime"
echo "$TIMEZONE" >"$ROOT/etc/timezone"
sed -i -E "s/^XKBLAYOUT=.*/XKBLAYOUT=\"$KEYBOARD_LAYOUT\"/" "$ROOT/etc/default/keyboard" 2>/dev/null || true

# The first-boot jobs of Raspberry Pi OS: our image is complete (users, SSH, partitions).
# - no resize of the system partition: the data partition comes after it (we grow that one)
# - no user wizard / cloud-init: the users exist
cmd=$(cat "$ROOT/boot/firmware/cmdline.txt")
cmd=$(echo "$cmd" | tr ' ' '\n' | grep -vE '^(init=.*firstboot.*|systemd\.run.*|resize)$' | tr '\n' ' ')
cmd="${cmd% } cfg80211.ieee80211_regdom=$WIFI_COUNTRY"
echo "$cmd" >"$ROOT/boot/firmware/cmdline.txt"
echo "cmdline.txt now: $(cat "$ROOT/boot/firmware/cmdline.txt")"
for unit in userconfig.service rpi-resize.service rpi-resize-swap-file.service \
    cloud-init.service cloud-init-local.service cloud-init-main.service cloud-init-network.service \
    cloud-config.service cloud-final.service cloud-init-hotplugd.socket \
    regenerate_ssh_host_keys.service; do
    in_root systemctl disable "$unit" 2>/dev/null && echo "disabled $unit" || true
done
[ -d "$ROOT/etc/cloud" ] && touch "$ROOT/etc/cloud/cloud-init.disabled"
echo "what blocks Wi-Fi in the base image:"
grep -rlE 'rfkill|wifi-country|WirelessEnabled' "$ROOT"/usr/lib/udev/rules.d "$ROOT"/etc/udev/rules.d \
    "$ROOT"/usr/lib/systemd/system "$ROOT"/etc/systemd/system "$ROOT"/etc/NetworkManager \
    "$ROOT"/usr/lib/NetworkManager "$ROOT"/var/lib/NetworkManager "$ROOT"/usr/lib/raspberrypi-sys-mods 2>/dev/null |
    while read -r f; do echo "--- ${f#"$ROOT"}"; grep -nE 'rfkill|wifi-country|WirelessEnabled' "$f" | head -8; done
# Wi-Fi on: Raspberry Pi OS ships its saved radio state as "Wi-Fi blocked" (lifted by setting a
# country in raspi-config); systemd-rfkill would restore it at every boot.
for f in "$ROOT"/var/lib/systemd/rfkill/*wlan; do
    [ -e "$f" ] || continue
    echo "rfkill state $(basename "$f"): $(cat "$f") -> 0"
    echo 0 >"$f"
done
rm -f "$ROOT/boot/firmware/userconf.txt" "$ROOT/boot/firmware/user-data" "$ROOT/boot/firmware/network-config"

log "PHYLAX station files and services"
cp -a "$REPO/rootfs/." "$ROOT/"
cp "$REPO/boot/phylax-wifi.txt" "$ROOT/boot/firmware/phylax-wifi.txt"
sed -i "s/XKB_DEFAULT_LAYOUT=us/XKB_DEFAULT_LAYOUT=$KEYBOARD_LAYOUT/" "$ROOT/etc/systemd/system/phylax-kiosk.service"
in_root systemctl enable phylax-kiosk.service phylax-grow-data.service phylax-wifi-setup.service \
    NetworkManager.service
in_root systemctl set-default graphical.target
if [ "$DEV_SSH" = 1 ]; then
    rm -f "$ROOT"/etc/ssh/ssh_host_*
    in_root systemctl enable ssh.service phylax-ssh-keys.service
fi
# station marker: PHYLAX Suite shows the station-only settings when it exists
image_version="$(date -u +%Y%m%d)-$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo local)"
cat >"$ROOT/etc/phylax-station-release" <<EOF
IMAGE_VERSION=$image_version
IMAGE_KIND=$([ -n "$DEV_USER" ] && echo dev || echo production)
SUITE_VERSION=$suite_version
BASE=$base_name
EOF

log "Data partition: the kiosk user's home (PHYLAX Suite's data) and saved networks"
mkdir -p "$WORK/data"
mount "${LOOP}p3" "$WORK/data"
mkdir -p "$WORK/data/home" "$WORK/data/network"
cp -a "$ROOT/home/$KIOSK_USER" "$WORK/data/home/"
chmod 700 "$WORK/data/network"
umount "$WORK/data"
cat >>"$ROOT/etc/fstab" <<EOF
LABEL=$DATA_LABEL  /data  ext4  defaults,noatime  0  2
/data/home/$KIOSK_USER  /home/$KIOSK_USER  none  bind,x-systemd.requires-mounts-for=/data  0  0
/data/network  /etc/NetworkManager/system-connections  none  bind,x-systemd.requires-mounts-for=/data  0  0
EOF
mkdir -p "$ROOT/data"

log "Close"
rm -f "$ROOT/usr/sbin/policy-rc.d"
rm -f "$ROOT/etc/resolv.conf"
[ -e "$WORK/resolv.conf.image" ] || [ -L "$WORK/resolv.conf.image" ] && mv "$WORK/resolv.conf.image" "$ROOT/etc/resolv.conf"
for m in boot/firmware dev/pts dev proc sys run; do umount "$ROOT/$m"; done
umount "$ROOT"
e2fsck -fy "${LOOP}p2" || [ $? -le 1 ]
e2fsck -fy "${LOOP}p3" || [ $? -le 1 ]
losetup -d "$LOOP"
LOOP=""

mkdir -p "$OUT"
name="phylax-station-$image_version-dev"
[ -n "$DEV_USER" ] || name="phylax-station-$image_version"
mv "$IMG" "$OUT/$name.img"
xz -T0 -6 "$OUT/$name.img"
(cd "$OUT" && sha256sum "$name.img.xz" >"$name.img.xz.sha256")
cat >"$OUT/build-info.txt" <<EOF
image:  $name.img.xz
base:   $url
suite:  $(basename "$APPIMAGE") ($(sha256sum "$APPIMAGE" | cut -c1-16)...)
kind:   $([ -n "$DEV_USER" ] && echo "dev (login $DEV_USER, SSH $([ "$DEV_SSH" = 1 ] && echo on || echo off))" || echo production)
EOF
cat "$OUT/build-info.txt"
