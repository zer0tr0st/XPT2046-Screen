#!/bin/sh
# xpt2046-setup.sh - 3.5" SPI LCD with XPT2046 touch (ILI9486-class panels,
# e.g. Waveshare 3.5" (A), "3.5 inch RPi Display") for Raspberry Pi.
# Works on Alpine Linux and Debian / Raspberry Pi OS. Safe to re-run.
#
# Uses the overlays that ship with the Pi kernel (no downloads needed).
# By default it picks the first one available: waveshare35a, then piscreen.
#
# Usage: ./xpt2046-setup.sh [-o overlay] [-r rotate] [-s spi_speed] [-f fps] [-p params] [-u]
#   -o  kernel overlay name            (default: auto-detect)
#   -r  display rotation 0|90|180|270  (default: 90)
#   -s  SPI speed in Hz, e.g. 16000000 (default: overlay's default)
#   -f  frames per second, e.g. 30     (default: overlay's default)
#   -p  extra overlay params, e.g. drm (default: auto, see below)
#   -u  uninstall (remove this script's changes)
#
# With piscreen on kernels that no longer ship the fbtft driver, the script
# adds the "drm" parameter automatically (uses the kernel's ili9486 DRM driver).
set -eu

OVERLAY=""
ROTATE=90
SPEED=""
FPS=""
EXTRA=""
UNINSTALL=0
# Starting-point touch calibration; fine-tune later with xinput_calibrator
CALIBRATION="3932 300 294 3801"
SWAPAXES=1

log()  { printf '==> %s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
has_mod() { find /lib/modules -name "$1" 2>/dev/null | grep -q .; }

while getopts "o:r:s:f:p:uh" opt; do
  case $opt in
    o) OVERLAY=$OPTARG ;;
    r) ROTATE=$OPTARG ;;
    s) SPEED=$OPTARG ;;
    f) FPS=$OPTARG ;;
    p) EXTRA=$OPTARG ;;
    u) UNINSTALL=1 ;;
    *) sed -n '2,/^set -eu/p' "$0" | sed -e '$d' -e 's/^# \{0,1\}//'; exit 1 ;;
  esac
done

case $ROTATE in 0|90|180|270) ;; *) die "Rotation must be 0, 90, 180 or 270." ;; esac
[ "$(id -u)" = 0 ] || die "Run as root."

# ---------- detect OS ----------
. /etc/os-release
case "${ID:-} ${ID_LIKE:-}" in
  *alpine*)            OS=alpine ;;
  *debian*|*raspbian*) OS=debian ;;
  *) die "Unsupported OS: ${ID:-unknown}" ;;
esac
log "Detected OS: $OS"

# ---------- detect boot partition ----------
BOOT=""
for d in /boot/firmware /media/mmcblk0p1 /boot; do
  if [ -f "$d/config.txt" ]; then BOOT=$d; break; fi
done
[ -n "$BOOT" ] || die "Could not find boot partition (no config.txt)."
log "Boot partition: $BOOT"

WAS_RO=0
if grep -E " $BOOT .*[ ,]ro[ ,]" /proc/mounts >/dev/null 2>&1; then
  WAS_RO=1
  mount -o remount,rw "$BOOT"
fi

# Alpine regenerates config.txt on kernel updates; prefer usercfg.txt if used
CFG="$BOOT/config.txt"
if [ -f "$BOOT/usercfg.txt" ] || grep -q '^include usercfg.txt' "$CFG"; then
  CFG="$BOOT/usercfg.txt"
  touch "$CFG"
fi
CMD="$BOOT/cmdline.txt"

finish() {
  if [ "$OS" = alpine ] && command -v lbu >/dev/null 2>&1; then
    lbu commit >/dev/null 2>&1 || true   # no-op on non-diskless installs
  fi
  [ "$WAS_RO" = 1 ] && mount -o remount,ro "$BOOT" || true
}

# ---------- uninstall ----------
if [ "$UNINSTALL" = 1 ]; then
  log "Removing XPT2046 display configuration..."
  sed -i '/# BEGIN XPT2046/,/# END XPT2046/d' "$CFG"
  sed -i -e 's/ fbcon=map:10//' -e 's/ fbcon=font:VGA10x10//' "$CMD"
  rm -f /etc/X11/xorg.conf.d/99-spi-fbdev.conf \
        /etc/X11/xorg.conf.d/99-touch-xpt2046.conf
  finish
  log "Removed. Reboot to apply. Backups (*.bak) were left in $BOOT."
  exit 0
fi

# ---------- choose / verify the overlay (before installing anything) ----------
list_related() {
  ls "$BOOT/overlays" 2>/dev/null | grep -i -E 'piscreen|waveshare35|ili9486|ads7846|mipi|tft35' >&2 || true
}
if [ -z "$OVERLAY" ]; then
  for c in waveshare35a piscreen; do
    if [ -f "$BOOT/overlays/$c.dtbo" ]; then OVERLAY=$c; break; fi
  done
  if [ -z "$OVERLAY" ]; then
    warn "Neither waveshare35a nor piscreen found in $BOOT/overlays."
    warn "Related overlays on this system:"; list_related
    die "Pick one with -o <name> (without .dtbo)."
  fi
  log "Using overlay: $OVERLAY"
elif [ ! -f "$BOOT/overlays/$OVERLAY.dtbo" ]; then
  warn "Overlay '$OVERLAY' not found in $BOOT/overlays."
  warn "Related overlays on this system:"; list_related
  die "Pick one with -o <name> (without .dtbo)."
fi

# piscreen on kernels without fbtft: use the DRM driver instead
if [ -z "$EXTRA" ] && [ "${OVERLAY#piscreen}" != "$OVERLAY" ]; then
  if has_mod 'fb_ili9486*'; then
    :   # fbtft driver present, keep the default
  elif has_mod 'ili9486*'; then
    EXTRA=drm
    log "fbtft driver not found; using the DRM driver (param: drm)."
  fi
fi

# ---------- install packages ----------
log "Installing packages..."
case "$OS" in
  alpine)
    apk add --no-cache ca-certificates \
      xorg-server xinit xf86-video-fbdev xf86-input-evdev eudev
    apk add --no-cache xinput_calibrator >/dev/null 2>&1 || \
      warn "xinput_calibrator not available; install it later for touch tuning."
    setup-devd udev >/dev/null 2>&1 || true
    ;;
  debian)
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
      ca-certificates xserver-xorg xinit \
      xserver-xorg-video-fbdev xserver-xorg-input-evdev
    DEBIAN_FRONTEND=noninteractive apt-get install -y xinput-calibrator >/dev/null 2>&1 || \
      warn "xinput-calibrator not available; install it later for touch tuning."
    ;;
esac

# ---------- config.txt (idempotent, marker block) ----------
log "Updating $CFG..."
[ -f "$CFG.bak" ] || cp "$CFG" "$CFG.bak"

OVL="$OVERLAY:rotate=$ROTATE"
[ -z "$SPEED" ] || OVL="$OVL,speed=$SPEED"
[ -z "$FPS" ]   || OVL="$OVL,fps=$FPS"
[ -z "$EXTRA" ] || OVL="$OVL,$EXTRA"

# remove our old block and any conflicting display overlays / duplicate SPI lines
sed -i '/# BEGIN XPT2046/,/# END XPT2046/d' "$CFG"
sed -i '/# BEGIN MHS35/,/# END MHS35/d' "$CFG"
sed -i -e '/^dtparam=spi=on/d' \
       -e '/^dtoverlay=tft35a/d' \
       -e '/^dtoverlay=waveshare35/d' \
       -e '/^dtoverlay=piscreen/d' "$CFG"

cat >> "$CFG" <<EOF

# BEGIN XPT2046
dtparam=spi=on
dtoverlay=$OVL
# END XPT2046
EOF

# ---------- cmdline.txt (idempotent) ----------
log "Updating $CMD..."
[ -f "$CMD.bak" ] || cp "$CMD" "$CMD.bak"
grep -q 'fbcon=map:10'        "$CMD" || sed -i 's/[[:space:]]*$/ fbcon=map:10/' "$CMD"
grep -q 'fbcon=font:VGA10x10' "$CMD" || sed -i 's/[[:space:]]*$/ fbcon=font:VGA10x10/' "$CMD"

# ---------- X11 config ----------
log "Writing X11 config..."
mkdir -p /etc/X11/xorg.conf.d
rm -f /usr/share/X11/xorg.conf.d/99-fbturbo.conf \
      /etc/X11/xorg.conf.d/99-calibration.conf

cat > /etc/X11/xorg.conf.d/99-spi-fbdev.conf <<'EOF'
Section "Device"
    Identifier "SPI LCD"
    Driver     "fbdev"
    Option     "fbdev" "/dev/fb1"
EndSection
EOF

# The XPT2046 is handled by the kernel's ads7846 driver, which names the
# input device "ADS7846 Touchscreen".
cat > /etc/X11/xorg.conf.d/99-touch-xpt2046.conf <<EOF
Section "InputClass"
    Identifier   "XPT2046 touchscreen"
    MatchProduct "ADS7846 Touchscreen"
    Driver       "evdev"
    Option       "Calibration" "$CALIBRATION"
    Option       "SwapAxes"    "$SWAPAXES"
EndSection
EOF

# ---------- sanity check: kernel modules ----------
if ! has_mod 'fb_ili9486*' && ! has_mod 'ili9486*'; then
  warn "No ILI9486 display driver module found (fbtft or DRM). The panel will"
  warn "stay blank unless your kernel has it built in."
fi
has_mod 'ads7846*' || warn "ads7846 touch module not found; touch may not work."

finish
log "Done. Reboot to apply changes."
log "Overlay line: dtoverlay=$OVL"
log "After reboot, check:  ls /dev/fb*   and   dmesg | grep -i -E 'ili9486|ads7846'"
log "If the display is not /dev/fb1, edit /etc/X11/xorg.conf.d/99-spi-fbdev.conf."
log "If touch is offset or swapped, run xinput_calibrator under X and update"
log "/etc/X11/xorg.conf.d/99-touch-xpt2046.conf."
