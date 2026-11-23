#!/bin/sh
# PHYLAX station (Buildroot image): last touches to the system before it is packed.
set -eu

# station marker and versions (PHYLAX Suite's Settings > Station reads this file)
BR_VERSION=$(sed -n 's/^BUILDROOT_TAG=//p' "${BR2_EXTERNAL_PHYLAX_PATH}/buildroot.version")
cat > "${TARGET_DIR}/etc/phylax-station-release" <<REL
IMAGE_VERSION=${PHYLAX_IMAGE_VERSION:-local}
IMAGE_KIND=${PHYLAX_IMAGE_KIND:-dev}
SUITE_VERSION=none
BASE=Buildroot ${BR_VERSION}
REL
