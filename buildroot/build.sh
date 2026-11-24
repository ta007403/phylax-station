#!/bin/bash
# PHYLAX station, Buildroot image: fetch the pinned Buildroot release and build the image.
#
#   buildroot/build.sh [OUTPUT_DIR]        (default: buildroot-out next to the repo)
#
# PHYLAX_IMAGE_KIND: production (configs/phylax_station_defconfig) or dev (that plus
# board/phylax-station/dev.fragment).
# Environment: PHYLAX_SUITE_DIR (PHYLAX Suite's AppImage, extracted; required), PHYLAX_SUITE_VERSION,
# PHYLAX_IMAGE_VERSION,
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

: "${PHYLAX_SUITE_DIR:?PHYLAX_SUITE_DIR: the folder of PHYLAX Suite, its Linux arm64 AppImage extracted (see README.md)}"
export PHYLAX_SUITE_DIR="$(realpath "$PHYLAX_SUITE_DIR")"
export PHYLAX_IMAGE_KIND="${PHYLAX_IMAGE_KIND:-dev}"
export PHYLAX_IMAGE_VERSION="${PHYLAX_IMAGE_VERSION:-$(date -u +%Y%m%d)-$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo local)}"

# the image's settings: production, or production + the dev additions
mkdir -p "$OUT"
parts=("$HERE/configs/phylax_station_defconfig")
case "$PHYLAX_IMAGE_KIND" in
    production) ;;
    dev) parts+=("$HERE/board/phylax-station/dev.fragment") ;;
    *) echo "PHYLAX_IMAGE_KIND must be dev or production, not $PHYLAX_IMAGE_KIND" >&2; exit 1 ;;
esac
cat "${parts[@]}" >"$OUT/phylax_station_${PHYLAX_IMAGE_KIND}_defconfig"
make -C "$SRC" O="$OUT" BR2_EXTERNAL="$HERE" \
    BR2_DEFCONFIG="$OUT/phylax_station_${PHYLAX_IMAGE_KIND}_defconfig" defconfig
# every option must have survived (a misspelt or unavailable one is dropped); an option the dev
# additions set again counts with their value
missing=0
for part in "${parts[@]}"; do
    while IFS= read -r line; do
        case "$line" in ''|'#'*) continue ;; esac
        key="${line%%=*}"
        [ "$part" != "${parts[0]}" ] || [ "${#parts[@]}" = 1 ] ||
            ! grep -q "^$key=" "${parts[@]:1}" || continue
        grep -qxF "$line" "$OUT/.config" || { echo "Not in the configuration: $line" >&2; missing=1; }
    done <"$part"
done
[ "$missing" = 0 ] || exit 1
echo "Image kind: $PHYLAX_IMAGE_KIND"

make -C "$SRC" O="$OUT"
echo "Image: $OUT/images/sdcard.img"
