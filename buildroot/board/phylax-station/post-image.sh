#!/bin/bash
# PHYLAX station (Buildroot image): the eMMC image from the boot files and the system partition
# (after Buildroot's board/raspberrypi/post-image.sh, with our genimage.cfg.in).
set -euo pipefail

BOARD_DIR="$(dirname "$0")"
GENIMAGE_CFG="${BINARIES_DIR}/genimage.cfg"
GENIMAGE_TMP="${BUILD_DIR}/genimage.tmp"

# The boot line: the system partition read-only, under phylax-overlay-init's RAM layer (as the
# Raspberry Pi OS image); production: no serial console. Made anew from cmdline.txt each time.
cmdline=$(cat "${BOARD_DIR}/cmdline.txt")
cmdline="${cmdline} ro init=/usr/local/sbin/phylax-overlay-init"
if [ "${PHYLAX_IMAGE_KIND}" = production ]; then
	cmdline=$(echo "${cmdline}" | tr ' ' '\n' | grep -v '^console=ttyAMA' | tr '\n' ' ')
	cmdline="${cmdline% }"
fi
echo "${cmdline}" > "${BINARIES_DIR}/rpi-firmware/cmdline.txt"
echo "cmdline.txt: ${cmdline}"

# The data partition (label PHYLAXDATA; it grows to fill the eMMC at the first start): the kiosk
# user's home and the saved networks, owned as on the station (made as root, in fakeroot)
DATA_TMP="${BUILD_DIR}/phylax-data"
rm -rf "${DATA_TMP}" "${BINARIES_DIR}/data.ext4"
mkdir -p "${DATA_TMP}/home/phylax" "${DATA_TMP}/network"
"${HOST_DIR}/bin/fakeroot" -- sh -c "
	chown 1100:1100 '${DATA_TMP}/home/phylax' && chmod 700 '${DATA_TMP}/home/phylax' &&
	chown 0:0 '${DATA_TMP}' '${DATA_TMP}/home' '${DATA_TMP}/network' && chmod 700 '${DATA_TMP}/network' &&
	'${HOST_DIR}/sbin/mke2fs' -q -t ext4 -L PHYLAXDATA -d '${DATA_TMP}' '${BINARIES_DIR}/data.ext4' 256M"

FILES=()
for i in "${BINARIES_DIR}"/*.dtb "${BINARIES_DIR}"/rpi-firmware/*; do
	FILES+=( "${i#${BINARIES_DIR}/}" )
done
KERNEL=$(sed -n 's/^kernel=//p' "${BINARIES_DIR}/rpi-firmware/config.txt")
FILES+=( "${KERNEL}" )
# the Wi-Fi file the owner fills in on the PC after flashing (the repo's boot/, as Raspberry Pi OS)
cp "${BR2_EXTERNAL_PHYLAX_PATH}/../boot/phylax-wifi.txt" "${BINARIES_DIR}/phylax-wifi.txt"
FILES+=( "phylax-wifi.txt" )
BOOT_FILES=$(printf '\\t\\t\\t"%s",\\n' "${FILES[@]}")
sed "s|#BOOT_FILES#|${BOOT_FILES}|" "${BOARD_DIR}/genimage.cfg.in" > "${GENIMAGE_CFG}"

ROOTPATH_TMP="$(mktemp -d)"
trap 'rm -rf "${ROOTPATH_TMP}"' EXIT
rm -rf "${GENIMAGE_TMP}"
genimage \
	--rootpath "${ROOTPATH_TMP}" \
	--tmppath "${GENIMAGE_TMP}" \
	--inputpath "${BINARIES_DIR}" \
	--outputpath "${BINARIES_DIR}" \
	--config "${GENIMAGE_CFG}"
