# PHYLAX station - Buildroot image

A second way to build the station's eMMC image: everything compiled from a pinned
[Buildroot](https://buildroot.org) release, so the image holds only what is listed in
`configs/phylax_station_defconfig`, and every package and version is known. It is built beside the
Raspberry Pi OS image (the repo's main README), which stays as it is: flash either one to compare.

- **Buildroot:** `buildroot.version` (long-term release, commit checked)
- **Settings:** `configs/phylax_station_defconfig` (the production image); the dev image adds
  `board/phylax-station/dev.fragment` (the console user `admin` with sudo, `lsusb`, `nmtui`)
- **Station files:** `board/phylax-station/` (boot `config.txt`, `cmdline.txt`, partitions, users)

## Milestones

| | Goal | State |
|---|---|---|
| 1 | Boots the CM5 to a console: kernel, eMMC, screen (dev image) | done: boots in 6.2 s |
| 2 | PHYLAX Suite in the kiosk; keyboard, trackpad; the blocks on USB | done: boots in 6.8 s |
| 3 | Settings > Station: Wi-Fi, Ethernet, Shut down / Restart, versions; start-up sound | done |
| 4 | Read-only system with the data partition; production and dev images; image checks | **now** |
| 5 | Compared with the Raspberry Pi OS image: boot time, size, packages | |

## Get the image

GitHub → this repo → **Actions** → **Build Buildroot image** → the newest green run → artifact
**phylax-station-br-dev-image** (`phylax-station-br-…-dev.img.xz`) or **phylax-station-br-image**
(production: `phylax-station-br-….img.xz`), each with its `.sha256` and `…-packages.tsv` (every
package in the image: name, version, licence). Every image is checked before upload
(`check-image.sh`). PHYLAX Suite is the newest successful "[PHYLAX] Build suite-desktop for Linux
arm64" run of phylax-suite (another run: start the workflow by hand with its run id), as for the
Raspberry Pi OS image. Flash it as in the main README (rpiboot, Raspberry Pi Imager).

As on the Raspberry Pi OS image: the system is read-only (a RAM layer over it: pulling the power
cannot damage it; dev: `sudo phylax-system-rw on|off`), PHYLAX Suite's data and the saved networks
are on the data partition, which grows to fill the eMMC at the first start. Production: no login
of any kind, no consoles, no switching away from PHYLAX Suite.

## Front status LED

A green LED on GPIO17 (header pin 11 → 330 Ω → LED → GND, pin 9), Buildroot image only:

| LED | Meaning |
|---|---|
| blinks once a second | starting (from the kernel's start), or PHYLAX Suite is not running |
| steady | PHYLAX Suite runs |
| off | shut down: safe to unplug (or no power) |

`config.txt` (`gpio-led` overlay), `phylax-status-led`, the kiosk's drop-in and a systemd
shut-down hook. Off for the first second or two after power on (the Raspberry Pi firmware).

## Milestone 4: what to check on the station

Dev image:
1. Everything from milestone 3 still works (Suite, blocks, Wi-Fi, sound, Shut down / Restart).
2. Ctrl+Alt+F2, `admin` / `123456`: `phylax-system-rw` says read-only; `df -h /data` shows the
   data partition grown to the rest of the eMMC.
3. Pull the power while Suite runs, then start again: it starts normally, and Suite's settings and
   the saved Wi-Fi are still there.
4. `systemd-analyze` (the boot time with the RAM layer).

Production image: Suite starts; Ctrl+Alt+F2 does nothing; Suite, Wi-Fi and the blocks work.

## Milestone 3 (passed): what was checked

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
`PHYLAX_SUITE_DIR=<extracted folder> PHYLAX_IMAGE_KIND=dev|production buildroot/build.sh [OUTPUT_DIR]`;
then `sudo buildroot/check-image.sh OUTPUT_DIR/images/sdcard.img dev|production`.
