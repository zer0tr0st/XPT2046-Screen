# XPT2046 3.5" SPI Screen Setup for Raspberry Pi

Setup script for **3.5" SPI LCDs with an XPT2046 touch controller** on a Raspberry Pi. These are the common 480×320 ILI9486-class panels sold as the Waveshare 3.5" (A), "3.5 inch RPi Display", and similar clones.

Works on **Alpine Linux** and **Debian / Raspberry Pi OS**. It uses the display overlays that ship with your kernel, so there is nothing to download.

| File | Purpose |
| --- | --- |
| `xpt2046-setup.sh` | Configures the display, touch input, and Linux console |
| `screen-info.sh` | Optional full-screen, large-font system status display |

## What the Setup Script Does

- Detects the OS (Alpine or Debian) and the boot partition path
- Auto-selects a kernel overlay: `waveshare35a` if available, otherwise `piscreen`
- Switches `piscreen` to the kernel's DRM driver (`drm` parameter) when the older `fbtft` driver isn't present
- Installs the X server, `fbdev` and `evdev` drivers, and `xinput_calibrator` (when available)
- Enables SPI and adds the display overlay with your chosen rotation
- Configures the Linux console to use the SPI display
- Writes X11 display and touch configuration
- Makes one-time backups of the boot config files
- Is safe to re-run: its changes live in a marked block and are never duplicated
- Removes the other screen's config block, so overlays don't conflict

## Installation

```sh
git clone https://github.com/zer0tr0st/XPT2046-Screen.git
cd XPT2046-Screen
chmod +x xpt2046-setup.sh
sudo ./xpt2046-setup.sh
sudo reboot
```

On Alpine without `sudo`, run `./xpt2046-setup.sh` as root.

## Options

```sh
./xpt2046-setup.sh [-o overlay] [-r rotate] [-s spi_speed] [-f fps] [-p params] [-u]
```

| Option | Default | Description |
| --- | --- | --- |
| `-o` | auto-detect | Kernel overlay name, without `.dtbo` |
| `-r` | `90` | Display rotation: `0`, `90`, `180`, or `270` |
| `-s` | overlay default | SPI speed in Hz, e.g. `16000000` |
| `-f` | overlay default | Frames per second, e.g. `30` |
| `-p` | auto | Extra overlay parameters, e.g. `drm` |
| `-u` | | Uninstall: remove this script's changes |

Examples:

```sh
sudo ./xpt2046-setup.sh                       # auto-detect, rotate 90
sudo ./xpt2046-setup.sh -r 270 -s 16000000    # different rotation and SPI speed
sudo ./xpt2046-setup.sh -o piscreen -p drm    # force piscreen with the DRM driver
sudo ./xpt2046-setup.sh -u                    # undo everything
```

## Requirements

- Raspberry Pi (developed on a Raspberry Pi 4)
- 3.5" SPI LCD with XPT2046 touch
- Alpine Linux (64-bit) or Debian / Raspberry Pi OS
- Internet connection (to install packages)
- Root access

## After Rebooting

Check that the display and touch were detected:

```sh
ls /dev/fb*
dmesg | grep -i -E 'ili9486|ads7846'
```

With the DRM driver the screen may not be `/dev/fb1`. If it isn't, update the path in `/etc/X11/xorg.conf.d/99-spi-fbdev.conf`.

## Files Changed

| File | Change |
| --- | --- |
| `config.txt` or `usercfg.txt` (boot partition) | Marked block with `dtparam=spi=on` and the display overlay |
| `cmdline.txt` (boot partition) | `fbcon=map:10 fbcon=font:VGA10x10` added |
| `/etc/X11/xorg.conf.d/99-spi-fbdev.conf` | X11 framebuffer driver for the SPI display |
| `/etc/X11/xorg.conf.d/99-touch-xpt2046.conf` | Touch calibration |

The boot partition is `/boot` on older Raspberry Pi OS, `/boot/firmware` on newer Debian, and `/media/mmcblk0p1` on Alpine diskless installs. The script finds it automatically and saves `.bak` copies of the files it edits.

## Touch Calibration

The script installs a starting-point calibration that may need adjusting for your screen and rotation. Run `xinput_calibrator` under X, then copy the values it prints into `/etc/X11/xorg.conf.d/99-touch-xpt2046.conf`.

## Status Screen (`screen-info.sh`)

Fills the LCD with a large, easy-to-read system overview, refreshed every 2 seconds:

- Hostname, date, and time
- IP address of each network interface
- Wi-Fi SSID and signal strength
- Gateway and internet reachability
- CPU usage and load
- Temperature in Celsius
- Memory and disk usage
- Uptime
- Undervoltage / throttling warning (only when there is a problem)
- Pi model, OS, and kernel version

Values are colored green, yellow, or red depending on how healthy they are.

```sh
sh screen-info.sh once           # draw once in the current terminal (test over SSH)
sudo sh screen-info.sh install   # install dependencies and start at boot
sudo sh screen-info.sh uninstall # remove the service and restore the login prompt
```

`install` uses OpenRC on Alpine and systemd on Debian, and takes over `tty1`, so the login prompt no longer appears on the LCD. Use SSH to log in, or run `uninstall` to restore it.

| Variable | Default | Description |
| --- | --- | --- |
| `FONT_SIZE` | `24` | Console font height: `16`, `20`, `24`, `28`, or `32` |
| `REFRESH` | `2` | Seconds between updates |
| `TTY` | `/dev/tty1` | Console to draw on |

At the default size the 480×320 screen fits about 40 columns by 13 rows.

## Alpine Notes

- Alpine regenerates `config.txt` on kernel updates, so display settings go in `usercfg.txt` when available.
- On **diskless** installs the script runs `lbu commit` so changes survive a reboot. If you edit anything in `/etc` by hand, run `lbu commit` yourself.
- The boot partition is read-only on diskless installs. The script remounts it read-write temporarily and restores it afterwards.

## Troubleshooting

- **`Overlay '...' not found`:** your kernel doesn't ship that overlay. The script lists the related overlays it finds. Pick one with `-o`.
- **Blank screen after reboot:** the panel needs a kernel display driver. The script warns if it can't find one. Check with:
  ```sh
  find /lib/modules -name 'fb_ili9486*' -o -name 'ili9486*'
  ```
  If neither exists, the overlay can't work on that kernel.
- **No touch:** check for the `ads7846` module and look for `ADS7846 Touchscreen` in `/proc/bus/input/devices`.
- **Touch is offset or inverted:** recalibrate with `xinput_calibrator` (see above).
- **No Terminus font in `screen-info.sh`:** install `kbd` and `terminus-font` (Alpine) or `kbd` and `console-setup` (Debian).
- **Script fails partway:** run it with `sh -x xpt2046-setup.sh` to see which line failed.

## Notes

This project targets XPT2046-touch 3.5" SPI displays. A reboot is required after setup. Behavior depends on your kernel, so results can vary between kernel versions.
