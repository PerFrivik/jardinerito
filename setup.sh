#!/usr/bin/env bash
# Jardinerito setup: installs the tools, flashes the firmware (if needed),
# then walks you through Wi-Fi, calibration and iPhone notifications.
#
#   ./setup.sh             full setup
#   ./setup.sh flash       only flash the firmware over USB
#   ./setup.sh calibrate   only redo the calibration
#   ./setup.sh notify      only set up phone notifications
#
# Works on macOS and Linux. Needs Python 3.11+ and the computer on the same Wi-Fi as Jardinerito.
set -euo pipefail
cd "$(dirname "$0")"

ESPHOME_VERSION="2026.10.0"
YAML="jardinerito.yaml"
DEVICE_IP=""

# ---------------------------------------------------------------- helpers
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
red()   { printf '\033[31m%s\033[0m\n' "$*"; }
step()  { echo; bold "== $* =="; }
pause() { read -r -p "${1:-Press Enter to continue...} " _; }
ask_yes() {  # ask_yes "question" [default y|n]
  local def="${2:-y}" ans
  read -r -p "$1 [$( [ "$def" = y ] && echo Y/n || echo y/N )] " ans
  ans="${ans:-$def}"
  [[ "$ans" == [Yy]* ]]
}
countdown() {
  local i
  for ((i = $1; i > 0; i--)); do printf '\r  %2d s ' "$i"; sleep 1; done
  printf '\r       \r'
}
urlencode() { python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"; }

# Talk to the device's web page (same API the settings page uses)
api_get()   { curl -fsS --max-time 5 "http://$DEVICE_IP/$1/$(urlencode "$2")"; }
api_post()  { curl -fsS --max-time 5 -X POST -d '' "http://$DEVICE_IP/$1/$(urlencode "$2")/$3${4:-}" >/dev/null; }
lost()      { red "Lost connection to Jardinerito at http://$DEVICE_IP. Check it's powered and on Wi-Fi, then try again."; exit 1; }
press()     { api_post button "$1" press || lost; }
set_text()  { api_post text "$1" set "?value=$(urlencode "$2")" || lost; }
number_value() {  # value of a number entity, e.g. a saved calibration voltage
  { api_get number "$1" || echo '{}'; } |
    python3 -c 'import sys, json
try: print("%.3f" % float(json.load(sys.stdin)["value"]))
except Exception: print("")'
}

# ---------------------------------------------------------------- steps
install_tools() {
  step "Installing tools"
  if ! command -v python3 >/dev/null; then
    red "Python 3 is missing. Install it from https://www.python.org/downloads/ and run ./setup.sh again."
    exit 1
  fi
  if ! python3 -c 'import sys; sys.exit(sys.version_info < (3, 11))'; then
    red "Python $(python3 -V | cut -d' ' -f2) is too old (need 3.11+). Install a newer one from https://www.python.org/downloads/"
    exit 1
  fi
  [ -d .venv ] || python3 -m venv .venv
  # shellcheck disable=SC1091
  . .venv/bin/activate
  if [ "$(esphome version 2>/dev/null | awk '{print $2}')" != "$ESPHOME_VERSION" ]; then
    echo "Installing ESPHome $ESPHOME_VERSION (takes a minute)..."
    pip install -q --upgrade pip
    pip install -q "esphome==$ESPHOME_VERSION"
  fi
  if [ ! -f secrets.yaml ]; then
    # Password for wireless firmware updates. Only needed on this computer.
    echo "ota_password: \"$(python3 -c 'import secrets; print(secrets.token_urlsafe(12))')\"" > secrets.yaml
    echo "Created secrets.yaml (keep it, you need it for wireless updates)."
  fi
  green "Tools ready."
}

find_port() {
  local ports=()
  local p
  for p in /dev/cu.usbmodem* /dev/ttyACM*; do [ -e "$p" ] && ports+=("$p"); done
  if [ ${#ports[@]} -eq 0 ]; then
    return 1
  elif [ ${#ports[@]} -eq 1 ]; then
    PORT="${ports[0]}"
  else
    echo "Several devices found:"
    local i
    for i in "${!ports[@]}"; do echo "  $((i + 1))) ${ports[$i]}"; done
    read -r -p "Which one? " i
    PORT="${ports[$((i - 1))]}"
  fi
}

flash() {
  step "Flashing the firmware"
  echo "Plug Jardinerito into this computer with a USB-C data cable."
  pause
  until find_port; do
    red "No device found. Try another cable or USB port."
    pause "Press Enter to look again..."
  done
  echo "Found $PORT"
  if [ "$(uname)" = Linux ] && [ ! -w "$PORT" ]; then
    red "No permission to use $PORT. Run this once, log out and back in, then run ./setup.sh again:"
    echo "  sudo usermod -aG dialout $USER"
    exit 1
  fi
  echo "The first time this downloads a compiler and takes 10-15 minutes."
  until esphome run "$YAML" --device "$PORT" --no-logs; do
    red "Flashing didn't work. Put it in download mode:"
    echo "  hold the small reset button on the side for ~2 s until a green light turns on, then let go."
    ask_yes "Try again?" || exit 1
  done
  green "Flashed! Press the reset button on the side once (or replug it). The plant face should appear."
}

connect_wifi() {
  step "Wi-Fi"
  echo "1. On your iPhone, open Settings > Wi-Fi and join \"Jardinerito-Setup\" (password: plantlove)."
  echo "2. A page opens. Pick your home Wi-Fi and type its password."
  echo "   (No page? Open http://192.168.4.1 in Safari.)"
  echo "3. Wait ~20 s, then hold the button on Jardinerito for 2 s. The screen shows its IP address."
  echo "   This computer must be on the same home Wi-Fi."
  while true; do
    read -r -p "IP address on the screen (e.g. 192.168.1.42): " DEVICE_IP
    DEVICE_IP="${DEVICE_IP// /}"
    if curl -fsS --max-time 5 "http://$DEVICE_IP/" >/dev/null 2>&1; then
      green "Connected to Jardinerito at http://$DEVICE_IP"
      return
    fi
    red "Can't reach http://$DEVICE_IP. Check the number and that this computer is on the same Wi-Fi."
  done
}

calibrate() {
  step "Calibration (once)"
  echo "Jardinerito only waters by itself after this, so it can never flood the plant by accident."
  echo
  bold "Dry: hold the sensor in the air, not touching anything."
  pause "Press Enter when it's in the air, then keep it there..."
  countdown 25  # the sensor averages its readings, give it time to settle
  press "Calibrate DRY (sensor in air)"
  sleep 1
  local dry; dry="$(number_value "Calibration dry voltage")"
  green "Dry saved (${dry} V)."
  echo
  bold "Wet: put the sensor in a glass of water, up to the line printed on it. NOT deeper:"
  bold "     the top part isn't waterproof."
  pause "Press Enter when it's in the water, then keep it there..."
  countdown 25
  press "Calibrate WET (sensor in water)"
  sleep 1
  local wet; wet="$(number_value "Calibration wet voltage")"
  green "Wet saved (${wet} V)."
  if [ -n "$dry" ] && [ -n "$wet" ] && python3 -c "import sys; sys.exit(not ($dry - $wet < 0.03))"; then
    red "Dry and wet are very close. Is the sensor plugged in? Run ./setup.sh calibrate to try again."
  fi
}

notify() {
  step "iPhone notifications"
  echo "Jardinerito can message you when it waters, and when the water jar is empty."
  ask_yes "Set it up now?" || return 0
  local topic
  topic="jardinerito-$(python3 -c 'import secrets; print(secrets.token_hex(3))')"
  echo "1. Install \"ntfy\" from the App Store: https://apps.apple.com/app/ntfy/id1625396347"
  echo "2. In ntfy tap +, type this topic, tap Subscribe:  $(bold "$topic")"
  echo "   (Allow notifications when it asks.)"
  pause "Press Enter when you've subscribed..."
  set_text "ntfy topic" "$topic"
  sleep 1
  press "Send test notification"
  if ask_yes "A test message should arrive in a few seconds. Did it?"; then
    green "Notifications work."
  else
    red "Check the topic is exactly \"$topic\" in ntfy, then run ./setup.sh notify to try again."
  fi
}

plant_name() {
  local name
  read -r -p "What's the plant called? (Enter to skip) " name
  [ -n "$name" ] && set_text "Plant name" "$name" && green "Hola, $name!"
  return 0
}

next_steps() {
  step "All set! What to do now"
  cat <<EOF
1. Push the sensor into the soil up to the line, no deeper.
2. Put the intake tube in a jar of water. Point the outlet tube at the soil.
3. Press the button once: it pumps for 3 s. Water should drip onto the soil.
   (Press again to stop.)
4. Watch the face: happy = fine, yellow + sweat drop = thirsty (it will water itself),
   red "refill" = the jar is empty: refill it and press the button.

Settings (watering amounts, notifications, names): http://${DEVICE_IP:-<IP from the screen>}
Hold the button for 2 s any time to see the address again.
EOF
}

need_ip() { [ -n "$DEVICE_IP" ] || connect_wifi; }

# ---------------------------------------------------------------- main
case "${1:-all}" in
  flash)     install_tools; flash ;;
  calibrate) need_ip; calibrate ;;
  notify)    need_ip; notify ;;
  all)
    bold "Hola! Let's set up Jardinerito."
    install_tools
    if ask_yes "Does Jardinerito need the firmware installed? (No if it already shows a face)" n; then
      flash
    fi
    connect_wifi
    calibrate
    plant_name
    notify
    next_steps
    ;;
  *) sed -n '2,9p' "$0"; exit 1 ;;
esac
