# PHYLAX station - Buildroot image

A second way to build the station's eMMC image: everything compiled from a pinned
[Buildroot](https://buildroot.org) release, so the image holds only what is listed in
`configs/phylax_station_defconfig`, and every package and version is known. It is built beside the
Raspberry Pi OS image (the repo's main README), which stays as it is: flash either one to compare.

- **Buildroot:** `buildroot.version` (long-term release, commit checked)
- **Settings:** `configs/phylax_station_defconfig`
- **Station files:** `board/phylax-station/` (boot `config.txt`, `cmdline.txt`, partitions, users)

## Milestones

| | Goal | State |
|---|---|---|
| 1 | Boots the CM5 to a console: kernel, eMMC, screen (dev image) | **now** |
| 2 | PHYLAX Suite in the kiosk; keyboard, trackpad; the blocks on USB | |
| 3 | Settings > Station: Wi-Fi, Ethernet, Shut down / Restart, versions; start-up sound | |
| 4 | Read-only system with the data partition; production and dev images; image checks | |
| 5 | Compared with the Raspberry Pi OS image: boot time, size, packages | |

## Get the image

GitHub → this repo → **Actions** → **Build Buildroot image** → the newest green run → artifact
**phylax-station-br-dev-image**: `phylax-station-br-…-dev.img.xz`, its `.sha256`, and
`…-packages.tsv` (every package in the image: name, version, licence). Flash it as in the main
README (rpiboot, Raspberry Pi Imager). The first build takes a few hours; later ones reuse the
downloads and the compiler cache.

## Milestone 1: what to check on the station

Dev login on the screen: `admin` / `123456` (`sudo` works). There is no PHYLAX Suite yet.

1. It starts, and the boot text and then the login prompt show on the 7" screen.
2. Log in. `cat /etc/phylax-station-release` shows `BASE=Buildroot …`.
3. `systemd-analyze` shows how long the start took (the first number to compare later).
4. `lsusb` or `ls /dev/input`: the keyboard and the trackpad are there, and
   the keyboard types.
5. `df -h /` and `mount | grep ' / '`: the system partition is on the eMMC.

Build it yourself (x86_64 Linux with Buildroot's host tools): `buildroot/build.sh [OUTPUT_DIR]`.
