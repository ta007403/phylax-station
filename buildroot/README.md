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
| 1 | Boots the CM5 to a console: kernel, eMMC, screen (dev image) | done: boots in 6.2 s |
| 2 | PHYLAX Suite in the kiosk; keyboard, trackpad; the blocks on USB | done: boots in 6.8 s |
| 3 | Settings > Station: Wi-Fi, Ethernet, Shut down / Restart, versions; start-up sound | **now** |
| 4 | Read-only system with the data partition; production and dev images; image checks | |
| 5 | Compared with the Raspberry Pi OS image: boot time, size, packages | |

## Get the image

GitHub → this repo → **Actions** → **Build Buildroot image** → the newest green run → artifact
**phylax-station-br-dev-image**: `phylax-station-br-…-dev.img.xz`, its `.sha256`, and
`…-packages.tsv` (every package in the image: name, version, licence). PHYLAX Suite is the newest
successful "[PHYLAX] Build suite-desktop for Linux arm64" run of phylax-suite (another run: start the
workflow by hand with its run id), as for the Raspberry Pi OS image. Flash it as in the main
README (rpiboot, Raspberry Pi Imager). The first build takes a few hours; later ones reuse the
downloads and the compiler cache.

## Milestone 3: what to check on the station

1. The start-up sound plays while the station starts.
2. Ethernet: with a cable, Settings > Station shows it connected.
3. Wi-Fi in Settings > Station: the list of networks, connect with a password, forget a network.
4. Wi-Fi from the boot partition: after flashing, fill in `phylax-wifi.txt` on the PC; at the
   start the station joins it and the password is removed from the file.
5. Settings > Station shows the versions (image, PHYLAX Suite, `BASE=Buildroot …`).
6. Shut down and Restart from Settings > Station.
7. Ctrl+Alt+F2, `admin` / `123456`: `systemd-analyze`; `nmtui` manages networks there too.

Milestone 2 (passed): PHYLAX Suite starts by itself in the kiosk; keyboard, trackpad and every
PHYLAX block work; 6.8 s from power to the system's start.

Milestone 1 (passed): the boot text and console login on the screen, `systemd-analyze`
(2.7 s kernel + 3.5 s system), the keyboard and trackpad, the system partition on the eMMC.

Build it yourself (x86_64 Linux with Buildroot's host tools): extract PHYLAX Suite's Linux arm64
AppImage (as the workflow does, `unsquashfs -o <offset>`), then
`PHYLAX_SUITE_DIR=<extracted folder> buildroot/build.sh [OUTPUT_DIR]`.
