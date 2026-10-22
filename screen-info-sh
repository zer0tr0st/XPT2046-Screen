#!/bin/sh
# screen-info.sh - full-screen system status for a Pi's console / small SPI LCD.
# Works on Alpine (OpenRC) and Debian / Raspberry Pi OS (systemd).
#
#   sh screen-info.sh once        draw once in the current terminal (test over SSH)
#   sh screen-info.sh run         draw continuously on $TTY (default /dev/tty1)
#   sh screen-info.sh install     install deps + autostart service
#   sh screen-info.sh uninstall   remove service, restore login on tty1
#
# Env: TTY=/dev/tty1  FONT_SIZE=24 (16|20|24|28|32)  REFRESH=2  FONT=<name>

TTY=${TTY:-/dev/tty1}
FONT_SIZE=${FONT_SIZE:-24}
REFRESH=${REFRESH:-2}
DEST=/usr/local/bin/screen-info.sh
SVC=pi-screen

ESC=$(printf '\033')
C_RST="${ESC}[0m"
C_BAR="${ESC}[30;46m"
C_LBL="${ESC}[36m"
C_VAL="${ESC}[1;37m"
C_OK="${ESC}[1;32m"
C_WARN="${ESC}[1;33m"
C_BAD="${ESC}[1;31m"

ROWS=13; COLS=40
PREV_TOT=0; PREV_IDLE=0
NET="..."; TICK=0
TMP=$(mktemp 2>/dev/null || echo "/tmp/pi-screen.$$")

die() { echo "ERROR: $*" >&2; exit 1; }

enable_community() {  # Alpine: make sure the community repo is enabled
  [ -f /etc/apk/repositories ] || return 0
  grep -qE '^[^#].*/community' /etc/apk/repositories && return 0
  echo "==> Enabling Alpine community repository..."
  sed -i -E 's|^#(.*/community)$|\1|' /etc/apk/repositories
  if ! grep -qE '^[^#].*/community' /etc/apk/repositories; then
    main=$(grep -E '^[^#].*/main$' /etc/apk/repositories | head -n1)
    [ -n "$main" ] && echo "${main%/main}/community" >> /etc/apk/repositories
  fi
  apk update
}

# ---------- helpers ----------
row() {  # row LABEL VALUE [COLOR]
  _l=$(printf '%-6.6s' "$1")
  _v=$(printf '%s' "$2" | cut -c1-$((COLS-7)))
  printf '%s%s %s%s%s\n' "$C_LBL" "$_l" "${3:-$C_VAL}" "$_v" "$C_RST"
}

lvl() {  # lvl VALUE WARN BAD -> color (higher = worse)
  if [ "$1" -ge "$3" ]; then printf '%s' "$C_BAD"
  elif [ "$1" -ge "$2" ]; then printf '%s' "$C_WARN"
  else printf '%s' "$C_OK"; fi
}

net_check() {
  if ping -c1 -W2 1.1.1.1 >/dev/null 2>&1; then NET=up; else NET=down; fi
}

# ---------- build one screen of text ----------
build() {
  # header: hostname on a colored bar
  printf '%s %s%s[K%s\n' "$C_BAR" "$(hostname | cut -c1-$((COLS-1)))" "$ESC" "$C_RST"
  row TIME "$(date '+%a %d %b %H:%M:%S')"

  # IPv4 addresses (skip loopback and container bridges)
  ips=$(ip -4 -o addr show 2>/dev/null | awk '$2!="lo" && $2!~/^(docker|veth|br-)/ {split($4,a,"/"); print $2, a[1]}')
  if [ -n "$ips" ]; then
    printf '%s\n' "$ips" | while read -r ifc addr; do row "$ifc" "$addr"; done
  else
    row IP "no address" "$C_BAD"
  fi

  # Wi-Fi SSID + signal
  for dir in /sys/class/net/*/wireless; do
    [ -d "$dir" ] || continue
    w=${dir%/wireless}; w=${w##*/}
    ssid=""; sig=""
    if command -v iw >/dev/null 2>&1; then
      l=$(iw dev "$w" link 2>/dev/null)
      ssid=$(printf '%s\n' "$l" | sed -n 's/^[[:space:]]*SSID: //p')
      sig=$(printf '%s\n' "$l" | sed -n 's/^[[:space:]]*signal: \(.*\) dBm.*/\1/p')
    fi
    [ -n "$ssid" ] || ssid=$(wpa_cli -i "$w" status 2>/dev/null | sed -n 's/^ssid=//p')
    [ -n "$ssid" ] || ssid=$(iwgetid -r "$w" 2>/dev/null)
    if [ -n "$ssid" ]; then
      if [ -n "$sig" ]; then
        row WiFi "$ssid ${sig}dBm" "$(lvl $((0-sig)) 60 75)"
      else
        row WiFi "$ssid" "$C_OK"
      fi
    else
      row WiFi "not connected" "$C_BAD"
    fi
  done

  # Gateway + internet reachability
  gw=$(ip route 2>/dev/null | awk '/^default/{print $3; exit}')
  if [ -n "$gw" ]; then
    case $NET in
      up)   row GW "$gw  online" "$C_OK" ;;
      down) row GW "$gw  no internet" "$C_WARN" ;;
      *)    row GW "$gw" ;;
    esac
  else
    row GW "none" "$C_BAD"
  fi

  # CPU usage (delta since last draw) + load
  read -r _c u n s i w q sq st _r < /proc/stat
  tot=$((u+n+s+i+w+q+sq+st)); idl=$((i+w))
  dt=$((tot-PREV_TOT)); di=$((idl-PREV_IDLE))
  if [ "$dt" -gt 0 ]; then cpu=$(( (100*(dt-di))/dt )); else cpu=0; fi
  PREV_TOT=$tot; PREV_IDLE=$idl
  row CPU "${cpu}%  load $(cut -d' ' -f1 /proc/loadavg)"

  # Temperatures in Celsius (every thermal zone), colored by the hottest one
  temps=""; hot=0
  for z in /sys/class/thermal/thermal_zone*/temp; do
    [ -r "$z" ] || continue
    mc=$(cat "$z" 2>/dev/null) || continue
    [ -n "$mc" ] || continue
    t=$((mc/1000))
    [ "$t" -gt "$hot" ] && hot=$t
    temps="${temps:+$temps  }${t}.$(( (mc%1000)/100 ))C"
  done
  [ -n "$temps" ] && row TEMP "$temps" "$(lvl "$hot" 60 75)"

  # Power / throttling warning (only shown if there is a problem)
  if command -v vcgencmd >/dev/null 2>&1; then
    th=$(vcgencmd get_throttled 2>/dev/null | sed 's/.*=//')
    case $th in ""|0x0) ;; *) row PWR "undervolt/throttle $th" "$C_BAD" ;; esac
  fi

  # Memory
  set -- $(awk '/^MemTotal/{t=$2} /^MemAvailable/{a=$2} END{u=t-a; printf "%d %d %d", u/1024, t/1024, u*100/t}' /proc/meminfo)
  row MEM "$1/${2}M  $3%" "$(lvl "$3" 70 85)"

  # Disk (root)
  set -- $(df -Pk / 2>/dev/null | awk 'NR==2{p=$5; sub("%","",p); printf "%.1f %.1f %d", $3/1048576, $2/1048576, p}')
  [ -n "${3:-}" ] && row DISK "$1/${2}G  $3%" "$(lvl "$3" 80 92)"

  # Uptime
  up=$(cut -d. -f1 /proc/uptime)
  d=$((up/86400)); h=$((up%86400/3600)); m=$((up%3600/60))
  if [ "$d" -gt 0 ]; then ut="${d}d ${h}h ${m}m"; else ut="${h}h ${m}m"; fi
  row UP "$ut"

  # Static info (clipped first if the screen is short)
  [ -r /proc/device-tree/model ] && row MODEL "$(tr -d '\0' </proc/device-tree/model | sed 's/Raspberry Pi/RPi/')"
  row OS "$(. /etc/os-release 2>/dev/null; printf '%s' "$PRETTY_NAME")"
  row KERNEL "$(uname -r)"
}

# ---------- draw ----------
draw() {
  size=$(stty size <"$TTY" 2>/dev/null) || size="13 40"
  ROWS=${size% *}; COLS=${size#* }
  build >"$TMP" 2>/dev/null
  {
    printf '\033[H'
    awk -v r="$ROWS" -v e="$ESC" \
      'NR<=r { if (NR>1) printf "\n"; printf "%s%s[K", $0, e } END { printf "%s[J", e }' "$TMP"
  } >"$TTY"
}

# ---------- big console font ----------
set_font() {
  command -v setfont >/dev/null 2>&1 || { echo "setfont not found; run: sh $0 install" >&2; return 0; }
  s=$FONT_SIZE
  for n in ${FONT:-} "ter-v${s}b" "ter-u${s}b" "ter-1${s}b" \
           "Lat15-TerminusBold${s}x$((s/2))" "Uni3-TerminusBold${s}x$((s/2))"; do
    for dir in /usr/share/consolefonts /usr/share/kbd/consolefonts /usr/lib/kbd/consolefonts; do
      for ext in .psf.gz .psf .psfu.gz .psfu; do
        if [ -f "$dir/$n$ext" ] && setfont -C "$TTY" "$dir/$n$ext" 2>/dev/null; then
          return 0
        fi
      done
    done
  done
  # fallback: any Terminus font of the requested height, whatever it is named
  for dir in /usr/share/consolefonts /usr/share/kbd/consolefonts /usr/lib/kbd/consolefonts; do
    for f in "$dir"/ter-*"$s"b.psf* "$dir"/*Terminus*Bold"$s"x*.psf*; do
      if [ -f "$f" ] && setfont -C "$TTY" "$f" 2>/dev/null; then return 0; fi
    done
  done
  echo "No usable Terminus font (size $s) found. Install: apk add kbd terminus-font" >&2
  echo "(Debian: apt install kbd console-setup), or run: sh $0 install" >&2
}

run() {
  [ -w "$TTY" ] || die "Cannot write to $TTY (run as root?)"
  trap 'printf "\033[?25h" >"$TTY"; rm -f "$TMP"; exit 0' INT TERM
  dmesg -n 1 2>/dev/null
  set_font
  printf '\033[9;0]\033[?25l\033[2J' >"$TTY"   # no blanking, hide cursor, clear
  while :; do
    [ $((TICK % 5)) -eq 0 ] && net_check
    TICK=$((TICK+1))
    draw
    sleep "$REFRESH"
  done
}

# ---------- install / uninstall ----------
detect_os() {
  . /etc/os-release
  case "${ID:-} ${ID_LIKE:-}" in
    *alpine*)            OS=alpine ;;
    *debian*|*raspbian*) OS=debian ;;
    *) die "Unsupported OS: ${ID:-unknown}" ;;
  esac
}

install_svc() {
  [ "$(id -u)" = 0 ] || die "Run as root."
  detect_os
  echo "==> Installing packages ($OS)..."
  if [ "$OS" = alpine ]; then
    enable_community
    apk add --no-cache kbd terminus-font iw
  else
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y kbd console-setup iw
  fi

  echo "==> Installing $DEST..."
  [ "$(readlink -f "$0")" = "$DEST" ] || cp "$0" "$DEST"
  chmod 755 "$DEST"

  if [ "$OS" = alpine ]; then
    cat > /etc/init.d/$SVC <<'EOF'
#!/sbin/openrc-run
description="Pi status screen"
command="/usr/local/bin/screen-info.sh"
command_args="run"
command_background=true
pidfile="/run/pi-screen.pid"
depend() {
	need localmount
	after net
}
EOF
    chmod 755 /etc/init.d/$SVC
    # free tty1 from the login prompt
    sed -i 's|^tty1::|#tty1::|' /etc/inittab
    kill -HUP 1 2>/dev/null || true
    pkill -f 'getty.*tty1' 2>/dev/null || true
    rc-update add $SVC default
    rc-service $SVC restart
    if command -v lbu >/dev/null 2>&1; then
      lbu include "$DEST" 2>/dev/null || true
      lbu commit 2>/dev/null || true
    fi
  else
    cat > /etc/systemd/system/$SVC.service <<'EOF'
[Unit]
Description=Pi status screen
Conflicts=getty@tty1.service
After=multi-user.target

[Service]
ExecStart=/usr/local/bin/screen-info.sh run
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now $SVC
  fi
  echo "==> Done. Status screen is running on $TTY."
  echo "    Local login on tty1 is disabled; use SSH. Undo with: sh $0 uninstall"
}

uninstall_svc() {
  [ "$(id -u)" = 0 ] || die "Run as root."
  detect_os
  if [ "$OS" = alpine ]; then
    rc-service $SVC stop 2>/dev/null || true
    rc-update del $SVC default 2>/dev/null || true
    rm -f /etc/init.d/$SVC
    sed -i 's|^#tty1::|tty1::|' /etc/inittab
    kill -HUP 1 2>/dev/null || true
    command -v lbu >/dev/null 2>&1 && lbu commit 2>/dev/null || true
  else
    systemctl disable --now $SVC 2>/dev/null || true
    rm -f /etc/systemd/system/$SVC.service
    systemctl daemon-reload
    systemctl start getty@tty1.service 2>/dev/null || true
  fi
  rm -f "$DEST"
  echo "==> Removed."
}

case "${1:-run}" in
  run)       run ;;
  once)      TTY=$(tty); draw; echo ;;
  install)   install_svc ;;
  uninstall) uninstall_svc ;;
  *)         echo "Usage: $0 [run|once|install|uninstall]"; exit 1 ;;
esac
