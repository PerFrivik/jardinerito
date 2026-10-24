#!/usr/bin/env bash
# Jardinerito setup. Plug Jardinerito into this laptop with USB-C and run it.
# It connects Jardinerito to your Wi-Fi, calibrates the sensor in your
# plant's pot and, if you like, sets up phone notifications.
#
#   ./setup.sh             full setup
#   ./setup.sh wifi        only connect to (another) Wi-Fi
#   ./setup.sh calibrate   only redo the calibration (add the IP if it's not on USB)
#   ./setup.sh notify      only set up phone notifications
#
#   ./setup.sh flash       install/update the firmware over USB (builds it first, needs Python 3.11+)
#   ./setup.sh reset       erase Wi-Fi, calibration and names on the device (firmware stays)
#
# Needs Python 3.9+. The laptop must be on the same Wi-Fi you give Jardinerito.
set -euo pipefail
cd "$(dirname "$0")"

ESPHOME_VERSION="2026.10.0"
YAML="jardinerito.yaml"
DEVICE_IP=""
PORT=""

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
  for ((i = $1; i > 0; i--)); do printf '\r  %3d s ' "$i"; sleep 1; done
  printf '\r        \r'
}
urlencode() { python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"; }

# Talk to the device's web page (same API the settings page uses)
api_get()   { curl -fsS --max-time 5 "http://$DEVICE_IP/$1/$(urlencode "$2")"; }
api_post()  { curl -fsS --max-time 5 -X POST -d '' "http://$DEVICE_IP/$1/$(urlencode "$2")/$3${4:-}" >/dev/null; }
lost()      { red "Lost connection to Jardinerito at http://$DEVICE_IP. Check it's powered and on Wi-Fi, then try again."; exit 1; }
press()     { api_post button "$1" press || lost; }
set_text()  { api_post text "$1" set "?value=$(urlencode "$2")" || lost; }
live_volts() {  # current soil sensor voltage
  { api_get sensor "Soil sensor voltage" || echo '{}'; } |
    python3 -c 'import sys, json
try: print("%.3f" % float(json.load(sys.stdin)["value"]))
except Exception: print("")'
}
number_value() {  # value of a number entity, e.g. a saved calibration voltage
  { api_get number "$1" || echo '{}'; } |
    python3 -c 'import sys, json
try: print("%.3f" % float(json.load(sys.stdin)["value"]))
except Exception: print("")'
}

# Wi-Fi setup over the USB cable (Improv serial protocol, built into the firmware).
#   improv state  -> prints the device URL if it's already on Wi-Fi
#   improv wifi   -> sends JW_SSID / JW_PASS, prints the device URL
# Exit codes: 0 ok, 1 couldn't connect to that Wi-Fi, 2 no answer, 3 not on Wi-Fi yet
improv() {
  python - "$PORT" "$1" <<'PY'
import os, sys, time
import serial

port, mode = sys.argv[1], sys.argv[2]

def frame(kind, data):
    b = b"IMPROV" + bytes([1, kind, len(data)]) + data
    return b + bytes([sum(b) & 0xFF])

def rpc(cmd, payload=b""):
    return frame(0x03, bytes([cmd, len(payload)]) + payload)

s = serial.Serial()
s.port, s.baudrate, s.timeout = port, 115200, 0.2
s.dtr = s.rts = False  # don't reset the board when opening the port
s.open()
buf = b""

def packets(seconds):
    global buf
    end = time.time() + seconds
    while time.time() < end:
        buf += s.read(512)
        while True:
            i = buf.find(b"IMPROV")
            if i < 0:
                buf = buf[-5:]
                break
            if len(buf) < i + 9:
                break
            n = buf[i + 8]
            if len(buf) < i + 10 + n:
                break
            pkt, buf = buf[i:i + 10 + n], buf[i + 10 + n:]
            if sum(pkt[:-1]) & 0xFF == pkt[-1]:
                yield pkt[7], pkt[9:-1]

def urls(data):  # RPC result: command, length, then (length, string) pairs
    out, j = [], 2
    while j < len(data):
        n = data[j]
        out.append(data[j + 1:j + 1 + n].decode(errors="replace"))
        j += 1 + n
    return [u for u in out if u.startswith("http")]

if mode == "state":
    for attempt in range(10):
        s.write(rpc(0x02))  # get current state
        state = None
        for kind, data in packets(1.0):
            if kind == 0x01:
                state = data[0]
                if state != 0x04:
                    sys.exit(3)
            elif kind == 0x04 and urls(data):
                print(urls(data)[0])
                sys.exit(0)
        if state == 0x04:
            sys.exit(3)
    sys.exit(2)

ssid = os.environ["JW_SSID"].encode()
pw = os.environ["JW_PASS"].encode()
s.write(rpc(0x01, bytes([len(ssid)]) + ssid + bytes([len(pw)]) + pw))
for kind, data in packets(100):
    if kind == 0x02 and data and data[0] == 0x03:  # unable to connect
        sys.exit(1)
    if kind == 0x04 and data and data[0] == 0x01 and urls(data):
        print(urls(data)[0])
        sys.exit(0)
sys.exit(2)
PY
}

# ---------------------------------------------------------------- steps
need_python() {  # need_python 3 9
  if ! command -v python3 >/dev/null; then
    red "Python 3 is missing. Install it from https://www.python.org/downloads/ and run ./setup.sh again."
    exit 1
  fi
  if ! python3 -c "import sys; sys.exit(sys.version_info < ($1, $2))"; then
    red "Python $(python3 -V | cut -d' ' -f2) is too old (need $1.$2+). Install a newer one from https://www.python.org/downloads/"
    exit 1
  fi
}

# Small: only what's needed to talk to Jardinerito over USB
install_tools() {
  need_python 3 9
  [ -d .venv ] || python3 -m venv .venv
  # shellcheck disable=SC1091
  . .venv/bin/activate
  if ! python -c 'import serial' 2>/dev/null; then
    echo "Installing a small helper (one time)..."
    if ! pip install -q pyserial >.pip.log 2>&1; then
      cat .pip.log; red "Installing pyserial failed (see above)."; exit 1
    fi
  fi
}

# Big: the firmware build tools. Only needed for flash / reset.
install_esphome() {
  need_python 3 11
  install_tools
  if [ "$(esphome version 2>/dev/null | awk '{print $2}')" != "$ESPHOME_VERSION" ]; then
    echo "Installing ESPHome $ESPHOME_VERSION (takes a minute)..."
    if ! { pip install -q --upgrade pip && pip install -q "esphome==$ESPHOME_VERSION"; } >.pip.log 2>&1; then
      cat .pip.log; red "Installing ESPHome failed (see above)."; exit 1
    fi
  fi
  if [ ! -f secrets.yaml ]; then
    # Password for wireless firmware updates. Only needed on this laptop.
    echo "ota_password: \"$(python3 -c 'import secrets; print(secrets.token_urlsafe(12))')\"" > secrets.yaml
    echo "Created secrets.yaml (keep it, you need it for wireless updates)."
  fi
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

need_port() {
  [ -n "$PORT" ] || until find_port; do
    red "Jardinerito isn't connected. Plug it into this laptop with a USB-C data cable."
    pause "Press Enter to look again..."
  done
  if [ "$(uname)" = Linux ] && [ ! -w "$PORT" ]; then
    red "No permission to use $PORT. Run this once, log out and back in, then run ./setup.sh again:"
    echo "  sudo usermod -aG dialout $USER"
    exit 1
  fi
}

flash() {
  step "Installing the firmware"
  install_esphome
  need_port
  echo "The first time this downloads a compiler and takes 10-15 minutes."
  until esphome run "$YAML" --device "$PORT" --no-logs; do
    red "That didn't work. Put Jardinerito in download mode:"
    echo "  hold the small reset button on the side for ~2 s until a green light turns on, then let go."
    ask_yes "Try again?" || exit 1
  done
  echo "Press the reset button on the side once (or replug it)."
  pause "Press Enter when the plant face shows on the screen..."
  green "Firmware installed."
}

current_wifi() {  # name of the Wi-Fi this laptop is on, if we can tell
  if command -v nmcli >/dev/null; then
    nmcli -t -f active,ssid dev wifi 2>/dev/null | sed -n 's/^yes://p' | head -1
  fi
}

set_ip_from_url() { DEVICE_IP="${1#http://}"; DEVICE_IP="${DEVICE_IP%:80}"; DEVICE_IP="${DEVICE_IP%/}"; }

wifi_by_hand() {
  echo "Let's do it by hand instead:"
  echo "1. On a phone or laptop, join the Wi-Fi \"Jardinerito-Setup\" (password: plantlove)."
  echo "2. A page opens (or open http://192.168.4.1 in a browser). Pick your Wi-Fi and type its password."
  echo "3. Hold the button on Jardinerito for 2 s. The screen shows its IP address."
  read -r -p "IP address on the screen (e.g. 192.168.1.42): " DEVICE_IP
  DEVICE_IP="${DEVICE_IP// /}"
}

connect_wifi() {  # connect_wifi [force]  (force = choose a Wi-Fi even if it already has one)
  step "Wi-Fi"
  need_port
  local url rc=0
  url="$(improv state)" || rc=$?
  if [ "$rc" = 0 ] && [ "${1:-}" != force ]; then
    set_ip_from_url "$url"
    green "Jardinerito is already on Wi-Fi at http://$DEVICE_IP"
  elif [ "$rc" = 2 ]; then
    red "Jardinerito didn't answer over USB."
    wifi_by_hand
  else
    echo "Jardinerito joins your Wi-Fi through the USB cable."
    echo "It needs a 2.4 GHz Wi-Fi (most home Wi-Fi has one)."
    local here ssid pass
    here="$(current_wifi)"
    while true; do
      read -r -p "Wi-Fi name${here:+ [$here]}: " ssid
      ssid="${ssid:-$here}"
      read -r -s -p "Wi-Fi password: " pass; echo
      echo "Connecting (up to a minute)..."
      rc=0
      url="$(JW_SSID="$ssid" JW_PASS="$pass" improv wifi)" || rc=$?
      if [ "$rc" = 0 ]; then
        set_ip_from_url "$url"
        green "Connected! Jardinerito is at http://$DEVICE_IP"
        break
      elif [ "$rc" = 1 ]; then
        red "Couldn't join \"$ssid\". Check the name and password (capital letters count)."
      else
        red "No answer from Jardinerito."
        wifi_by_hand
        break
      fi
    done
  fi
  check_reachable
}

check_reachable() {
  until curl -fsS --max-time 5 "http://$DEVICE_IP/" >/dev/null 2>&1; do
    red "This laptop can't reach http://$DEVICE_IP. Is it on the same Wi-Fi as Jardinerito?"
    pause "Press Enter to try again..."
  done
}

calibrate() {
  step "Calibration (once)"
  echo "Jardinerito learns what dry and wet soil mean in your pot."
  echo "It only waters by itself after this, so it can never flood the plant by accident."
  echo
  bold "1. Push the sensor into the soil, up to the line printed on it. Not deeper:"
  bold "   the top part isn't waterproof. Leave it there for the rest of the calibration."
  pause
  echo
  echo "2. Push a finger 2 cm into the soil."
  local in_air=no
  if ask_yes "   Does it feel dry, like the plant could use water now?"; then
    echo "   Measuring dry soil..."
  else
    in_air=yes
    echo "   Then we use air as \"dry\". Pull the sensor out and hold it in the air, not touching anything."
    pause "   Press Enter when it's in the air, then keep it there..."
  fi
  countdown 25  # the sensor averages its readings, give it time to settle
  press "Calibrate DRY"
  sleep 1
  local dry; dry="$(number_value "Calibration dry voltage")"
  green "   Dry saved (${dry} V)."
  if [ "$in_air" = yes ]; then
    pause "   Push the sensor back into the soil, up to the line, then press Enter..."
  fi
  echo
  echo "3. Water the plant well by hand, until the soil is soaked."
  pause "   Press Enter when you've watered it..."
  echo "   Waiting 2 minutes for the water to spread..."
  countdown 120
  # Only save "wet" if the sensor clearly reads wetter than "dry" (lower voltage = wetter)
  local now
  while true; do
    now="$(live_volts)"
    if [ -n "$dry" ] && [ -n "$now" ] && python3 -c "import sys; sys.exit(not ($dry - $now >= 0.03))"; then
      break
    fi
    red "   The sensor doesn't feel the water yet (dry ${dry} V, now ${now:-?} V)."
    echo "   Make sure the soil around the whole sensor is soaked, up to the line."
    if ! ask_yes "   Check again in 1 minute?"; then
      red "Calibration isn't finished, so Jardinerito won't water by itself yet."
      echo "Run ./setup.sh calibrate to try again."
      return 1
    fi
    countdown 60
  done
  press "Calibrate WET"
  sleep 1
  local wet; wet="$(number_value "Calibration wet voltage")"
  green "   Wet saved (${wet} V). Calibration done!"
  if [ "$in_air" = yes ]; then
    echo "Tip: in a few days, when the soil feels dry, open the settings page and look at \"Soil moisture\"."
    echo "Set \"Water below moisture\" a little above that number."
  fi
}

plant_name() {
  local name
  echo
  read -r -p "What's the plant called? (Enter to skip) " name
  [ -n "$name" ] && set_text "Plant name" "$name" && green "Hola, $name!"
  return 0
}

notify() {
  step "Phone notifications (optional)"
  echo "Jardinerito can send a message to your phone when it waters, and when the water jar is empty."
  ask_yes "Set it up now?" n || return 0
  local topic
  topic="jardinerito-$(python3 -c 'import secrets; print(secrets.token_hex(3))')"
  echo "1. Install the free \"ntfy\" app on your phone (links on https://ntfy.sh)."
  echo "2. In ntfy, tap +, type this topic and subscribe:  $(bold "$topic")"
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

next_steps() {
  if [ "${CALIBRATED:-yes}" = no ]; then
    step "Almost done: calibration still missing"
    echo "Run ./setup.sh calibrate when the soil is soaked. Until then it won't water by itself."
  else
    step "All set! What to do now"
  fi
  cat <<EOF
1. Wait 1 minute, then unplug Jardinerito (it saves its settings once a minute).
2. Plug it into a USB-C charger next to the plant. The sensor stays in the soil.
3. Put the intake tube in a jar of water. Point the outlet tube at the soil.
4. Press the button once: it pumps for 3 s and water drips onto the soil. (Press again to stop.)
5. From now on it runs by itself. Watch the face:
   happy = fine, yellow + sweat drop = thirsty (it waters itself),
   "¡Agua, por favor!" = the jar is empty: refill it and press the button.
6. Big plant? Put the outlet tube in a measuring cup and press the button once to see how much one
   burst gives. Then set "Pump burst length" and "Max bursts per day" on the settings page.

Settings page (watering amounts, names, notifications): http://${DEVICE_IP:-<hold the button 2 s to see the address>}
EOF
}

reset_device() {
  step "Reset"
  install_esphome
  need_port
  echo "This erases Wi-Fi, calibration, names and notification settings on Jardinerito."
  echo "The firmware stays, so it's ready for ./setup.sh again."
  ask_yes "Erase them now?" n || exit 0
  # Find the settings ("nvs") partition in the device's own partition table, then erase only that.
  local tmp region
  tmp="$(mktemp)"
  python -m esptool --port "$PORT" read-flash 0x8000 0xc00 "$tmp" >/dev/null
  region="$(python - "$tmp" <<'PY'
import struct, sys
data = open(sys.argv[1], "rb").read()
for i in range(0, len(data), 32):
    magic, ptype, subtype, offset, size = struct.unpack_from("<HBBII", data, i)
    if magic == 0x50AA and ptype == 0x01 and subtype == 0x02:
        print(hex(offset), hex(size))
        break
PY
)"
  rm -f "$tmp"
  if [ -z "$region" ]; then
    red "Couldn't find the settings partition. Nothing was erased."
    exit 1
  fi
  # shellcheck disable=SC2086
  python -m esptool --port "$PORT" erase-region $region
  green "Done. Jardinerito restarts with no Wi-Fi and asks to be calibrated (\"¡Calíbrame!\")."
}

need_ip() {  # need_ip [ip]
  [ -n "$DEVICE_IP" ] && return
  if [ -n "${1:-}" ]; then
    DEVICE_IP="$1"
  elif find_port; then
    connect_wifi
    return
  else
    echo "Hold the button on Jardinerito for 2 s. The screen shows its IP address."
    read -r -p "IP address on the screen: " DEVICE_IP
    DEVICE_IP="${DEVICE_IP// /}"
  fi
  check_reachable
}

# ---------------------------------------------------------------- main
case "${1:-all}" in
  flash)     flash ;;
  reset)     reset_device ;;
  wifi)      install_tools; connect_wifi force ;;
  calibrate) install_tools; need_ip "${2:-}"; calibrate ;;
  notify)    install_tools; need_ip "${2:-}"; notify ;;
  all)
    bold "Hola! Let's set up Jardinerito."
    install_tools
    need_port
    connect_wifi
    calibrate || CALIBRATED=no
    plant_name
    notify
    next_steps
    ;;
  *) sed -n '2,14p' "$0"; exit 1 ;;
esac
