# PHYLAX station

The eMMC image of the **PHYLAX wallet station**: a Raspberry Pi CM5 with a 7" 1024×600 screen,
keyboard and trackpad, that starts straight into **PHYLAX Suite** with the PHYLAX blocks on USB.

- **Base:** official Raspberry Pi OS Lite 64-bit (checked against Raspberry Pi's checksum).
- **Kiosk:** [cage](https://github.com/cage-kiosk/cage) shows PHYLAX Suite fullscreen on boot, as
  the user `phylax` (no login, no desktop). If PHYLAX Suite closes, it starts again.
- **PHYLAX Suite:** the Linux arm64 build of [phylax-suite](https://github.com/ta007403/phylax-suite)
  (branch `phylax`), the same app as on Windows.
- **Partitions:** boot, system, **data**. The data partition holds PHYLAX Suite's data (settings,
  wallet names) and the saved Wi-Fi networks. On the first boot it grows to fill the eMMC.

## Dev image (now)

| | |
|---|---|
| Login (console and SSH) | `admin` / `123456`. Change it with `passwd` when you like. |
| SSH | on: `ssh admin@phylax-station.local` (or the station's IP address) |
| Console | **Ctrl+Alt+F2**, log in; **Ctrl+Alt+F1** back to PHYLAX Suite |
| Hostname, time zone, keyboard | `phylax-station`, Asia/Bangkok, US |

Production images will have no login and no SSH.

## Settings > Station

In PHYLAX Suite, **Settings > Station** (only on the station): Wi-Fi (scan, connect with a
password, forget), Ethernet status, **Shut down** / **Restart**, and the image's versions. A polkit
rule (`rootfs/etc/polkit-1/rules.d/50-phylax-station.rules`) lets the kiosk user do exactly this,
without a password.

## Get the image

GitHub → this repo → **Actions** → **Build station image** → the newest green run → artifact
**phylax-station-dev-image** (a zip with `phylax-station-…-dev.img.xz`, its `.sha256` and
`build-info.txt`). Unzip it; keep the `.img.xz` as it is.

A new image is built on every push to `main`, from the newest successful PHYLAX Suite Linux arm64
build. To pick another PHYLAX Suite build: **Run workflow** with its run id.

## Flash the eMMC (Windows)

1. Install [rpiboot](https://github.com/raspberrypi/usbboot) (`rpiboot_setup.exe`) and
   [Raspberry Pi Imager](https://www.raspberrypi.com/software/).
2. Put the carrier board in USB boot mode (its eMMC boot jumper/switch), connect it to the PC by
   USB, power it.
3. Run **rpiboot**: the eMMC appears as a USB drive (Windows may offer to format it: **Cancel**).
4. Raspberry Pi Imager: **Device** Raspberry Pi 5 / CM5 → **Operating system: Use custom** → the
   `.img.xz` → **Storage:** the eMMC → **Next** → **No** to OS customisation (the image is complete)
   → write.
5. **Wi-Fi** (no Ethernet cable): after writing, unplug and replug USB, run rpiboot again; open the
   small **bootfs** drive and edit `phylax-wifi.txt`:
   ```
   SSID=YourWiFi
   PASSWORD=your-wifi-password
   COUNTRY=TH
   ```
   Save, eject. On boot the station joins that Wi-Fi and removes the password from the file.
   Or later on the station: PHYLAX Suite → **Settings > Station** → *Scan for networks*.
6. Remove the USB boot jumper, power the station: PHYLAX Suite starts on the screen.

**Writing a whole image replaces everything on the eMMC, the data partition too.** An update that
replaces only the system and keeps the data partition comes with a later image.

## Build it yourself

On an arm64 Linux machine (or GitHub's `ubuntu-24.04-arm`), as root:

```bash
sudo build/build-image.sh PHYLAX-Suite-<version>-linux-arm64.AppImage out/
```

Settings (base image, sizes, hostname, dev login) are in `build/config.env`.

## Files

- `build/build-image.sh`: the image build (download, partitions, packages, PHYLAX Suite, users,
  services)
- `build/config.env`: its settings
- `build/check-image.sh`: checks a built image (partitions, PHYLAX Suite and its libraries,
  services, users, data partition); the GitHub build runs it
- `rootfs/`: files copied into the system: the kiosk service, the first-boot data partition grow,
  the Wi-Fi setup, SSH host keys made on each station's first boot
- `boot/phylax-wifi.txt`: the Wi-Fi file on the boot partition
- `.github/workflows/build-image.yml`: the GitHub build
