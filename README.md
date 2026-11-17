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

## Two images: production and dev

Every build makes both, from the same system:

| | **Production** (`phylax-station-…img.xz`) | **Dev** (`phylax-station-…-dev.img.xz`) |
|---|---|---|
| For | real stations | development and testing |
| Login | **none**: every account is locked | console only: `admin` / `123456` |
| Consoles | **none**: no login prompt on Ctrl+Alt+F2-F6 nor on the serial port; the kiosk does not switch away | **Ctrl+Alt+F2**, log in; **Ctrl+Alt+F1** back to PHYLAX Suite |
| SSH | none | none |
| Magic SysRq keys | off | on |
| Way in | **re-flash only** | the console |

Both: read-only system, hostname `phylax-station`, time zone Asia/Bangkok, US keyboard. Nothing on
the network can log in to either; updates are by re-flashing.

On a production station, everything is done in PHYLAX Suite (Wi-Fi, shut down and restart in
Settings > Station). If it ever needs fixing, re-flash it: that loses only the saved Wi-Fi and
PHYLAX Suite's settings. The wallets and keys are on the PHYLAX blocks, never on the station.

## Read-only system

The system partition is **read-only**: at start, `phylax-overlay-init` (before systemd) puts a RAM
layer over it, so everything the running system writes is in RAM and gone at the next start.
**Pulling the power cannot damage the system.** Shut down from Settings > Station anyway when you
can: the data partition (PHYLAX Suite's data, saved Wi-Fi) is still written when something changes
(ext4: it repairs itself at the next start).

- Kept on the data partition: PHYLAX Suite's data, saved Wi-Fi networks, the station's machine id
  (its network identity), and SSH host keys if an image has SSH (`DEV_SSH=1`).
- The boot partition is read-only too; it is made writable only to clean up `phylax-wifi.txt`.
- **Dev:** changes on the station (e.g. `apt install`) are lost at the next start. To keep them:
  `sudo phylax-system-rw on`, `sudo reboot`, make the changes, then `sudo phylax-system-rw off`,
  `sudo reboot`. `phylax-system-rw` shows the current state.
- If the RAM layer cannot be set up, the station starts with a writable system instead (a line
  "phylax-overlay: ..." on the screen at start says why).

## Start-up sound

`assets/PHYLAX_Startup_Sound.mp3`, trimmed and converted to `rootfs/usr/share/phylax/startup.wav`,
plays once at each start, as early as possible (`phylax-startup-sound`, while the boot text still
shows), on a 40 mm 4 Ω 3 W speaker through an **Adafruit MAX98357A I2S amp**:

| MAX98357A | 40-pin header | |
|---|---|---|
| Vin | pin 2 (or 4) | 5 V |
| GND | pin 6 | ground |
| BCLK | pin 12 | GPIO 18 |
| LRC | pin 35 | GPIO 19 |
| DIN | pin 40 | GPIO 21 |
| GAIN, SD | not connected | 9 dB; both channels mixed |

`config.txt` has `dtoverlay=max98357a`. Without the amp, nothing plays (no error). To change the
sound: replace the MP3 and convert it again with
`ffmpeg -i assets/PHYLAX_Startup_Sound.mp3 -af "silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.02,areverse,silenceremove=start_periods=1:start_threshold=-60dB:start_silence=0.15,areverse" -ar 48000 -ac 2 -sample_fmt s16 rootfs/usr/share/phylax/startup.wav`.

## Settings > Station

In PHYLAX Suite, **Settings > Station** (only on the station): Wi-Fi (scan, connect with a
password, forget), Ethernet status, **Shut down** / **Restart**, and the image's versions. A polkit
rule (`rootfs/etc/polkit-1/rules.d/50-phylax-station.rules`) lets the kiosk user do exactly this,
without a password.

## Get the image

GitHub → this repo → **Actions** → **Build station image** → the newest green run → artifact
**phylax-station-image** (production) or **phylax-station-dev-image** (dev): a zip with the
`.img.xz`, its `.sha256` and `build-info.txt`. Unzip it; keep the `.img.xz` as it is.

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
sudo IMAGE_KIND=production build/build-image.sh PHYLAX-Suite-<version>-linux-arm64.AppImage out/
sudo IMAGE_KIND=production build/check-image.sh out/*.img.xz
```

`IMAGE_KIND=dev` (the default) makes the dev image. Settings (base image, sizes, hostname, dev
login) are in `build/config.env`.

## Files

- `build/build-image.sh`: the image build (download, partitions, packages, PHYLAX Suite, users,
  services)
- `build/config.env`: its settings
- `build/check-image.sh`: checks a built image (partitions, PHYLAX Suite and its libraries,
  services, users, data partition); the GitHub build runs it
- `rootfs/`: files copied into the system: the read-only system (`phylax-overlay-init`,
  `phylax-system-rw`), the kiosk service, the first-boot data partition grow, the Wi-Fi setup, SSH
  host keys (made on each station's first start, kept on the data partition), the polkit rule
- `boot/phylax-wifi.txt`: the Wi-Fi file on the boot partition
- `.github/workflows/build-image.yml`: the GitHub build
