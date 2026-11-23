#!/bin/bash
# PHYLAX station, Buildroot image: fetch the pinned Buildroot release and build the image.
#
#   buildroot/build.sh [OUTPUT_DIR]        (default: buildroot-out next to the repo)
#
# Environment: PHYLAX_IMAGE_KIND (dev; production comes with milestone 4), PHYLAX_IMAGE_VERSION,
# BUILDROOT_SRC (where Buildroot is kept, default: OUTPUT_DIR/../buildroot-src).
# Needs an x86_64 Linux machine (the Bootlin toolchain is built for it) with Buildroot's usual
# host tools. The image is OUTPUT_DIR/images/sdcard.img.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(dirname "$HERE")"
OUT="$(realpath -m "${1:-$REPO/../buildroot-out}")"
SRC="$(realpath -m "${BUILDROOT_SRC:-$OUT/../buildroot-src}")"
# shellcheck source=buildroot.version
. "$HERE/buildroot.version"

if [ ! -d "$SRC/.git" ]; then
    git clone --quiet --depth 1 --branch "$BUILDROOT_TAG" https://gitlab.com/buildroot.org/buildroot.git "$SRC"
fi
actual="$(git -C "$SRC" rev-parse HEAD)"
if [ "$actual" != "$BUILDROOT_COMMIT" ]; then
    echo "Buildroot in $SRC is at $actual, expected $BUILDROOT_TAG = $BUILDROOT_COMMIT" >&2
    exit 1
fi
echo "Buildroot $BUILDROOT_TAG ($BUILDROOT_COMMIT)"

export PHYLAX_IMAGE_KIND="${PHYLAX_IMAGE_KIND:-dev}"
export PHYLAX_IMAGE_VERSION="${PHYLAX_IMAGE_VERSION:-$(date -u +%Y%m%d)-$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo local)}"

make -C "$SRC" O="$OUT" BR2_EXTERNAL="$HERE" phylax_station_defconfig
# every option of our defconfig must have survived (a misspelt or unavailable one is dropped)
missing=0
while IFS= read -r line; do
    case "$line" in ''|'#'*) continue ;; esac
    grep -qxF "$line" "$OUT/.config" || { echo "Not in the configuration: $line" >&2; missing=1; }
done < "$HERE/configs/phylax_station_defconfig"
[ "$missing" = 0 ] || exit 1

make -C "$SRC" O="$OUT"
echo "Image: $OUT/images/sdcard.img"
