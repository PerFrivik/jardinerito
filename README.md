# Jardinerito 🌱

A little gardener that lives next to your plant. It checks the soil, waters the plant by itself from a jar, shows how the plant is feeling and sends you a message on your phone.

| Happy | Thirsty | Drinking | Refill the jar |
|:---:|:---:|:---:|:---:|
| ![happy](docs/happy.gif) | ![thirsty](docs/thirsty.gif) | ![drinking](docs/drinking.gif) | ![refill jar](docs/sad.gif) |

<p align="center"><img src="docs/birthday.gif" width="200" alt="Happy Birthday Maria"></p>

## What's inside

- **M5Stack AtomS3R**: the brain. ESP32-S3 with Wi-Fi, a 0.85" screen and a button.
- **M5Stack Unit Watering**: a soil moisture sensor and a small pump in one unit.
- A Grove cable between them, and a USB-C power supply.

## Setting it up

1. **Plant:** push the sensor into the soil up to the line printed on it. Don't push it deeper, because the top part isn't waterproof.
2. **Water:** put the intake tube in a jar of water. Route the outlet tube so it drips onto the soil.
3. **Power:** plug in USB-C. The face appears.
4. **Wi-Fi:** on your phone, join the Wi-Fi network **`Jardinerito-Setup`** (password **`plantlove`**). A setup page opens; pick your home Wi-Fi.
   If it ever loses your Wi-Fi, the setup network comes back after about a minute.
5. **Settings page:** hold the button for 2 seconds. The screen shows its IP address. Open that address in a browser on the same Wi-Fi.

Watering works even without Wi-Fi. Wi-Fi is only needed for the settings page, phone messages and the night dimming (it needs the time).

## The button

| Press | What happens |
|---|---|
| Single press | Water now (press again to stop) |
| Double press | 🎂 |
| Hold 2 s | Wi-Fi info / IP address |

## Phone notifications (ntfy)

1. Install the free **ntfy** app ([iOS](https://apps.apple.com/app/ntfy/id1625396347) / [Android](https://play.google.com/store/apps/details?id=io.heckel.ntfy)).
2. Subscribe to a topic with a hard-to-guess name, for example `jardinerito-maria-7k2p`.
3. On the settings page, type the same name into **ntfy topic**, then press **Send test notification**.

You'll get a message when it waters, when the jar is probably empty, and if it hits its daily limit.

## How it waters

- Every 30 s it checks the soil. If moisture is below **"Water below moisture"** (default 35%), it pumps a short burst (default 3 s).
- Then it waits **"Soak time"** (default 15 min) so the water can spread before it measures again.
- It does at most **"Max bursts per day"** (default 6). The pump can never run longer than 15 s in one go.
- If 3 bursts in a row don't make the soil wetter, it assumes the jar is empty. It stops and asks you to refill it. Refill, then press the button (or **Jar refilled** on the settings page).
- The screen dims between 22:00 and 07:00. Pressing the button wakes it up.

All of these numbers can be changed on the settings page and are saved on the device.

## Calibration (needed once)

Auto-watering stays off until the sensor is calibrated, so it can never flood the plant by accident.

1. Hold the sensor in the air and press **Calibrate DRY (sensor in air)**.
2. Put it in a glass of water up to the line and press **Calibrate WET (sensor in water)**.
3. Put it back in the soil. If it waters too often or too rarely, adjust **Water below moisture**.

## Hacking on it

The firmware is [ESPHome](https://esphome.io). Everything is in [`jardinerito.yaml`](jardinerito.yaml): screen drawing, watering logic and settings.

```bash
python3 -m venv .venv && . .venv/bin/activate
pip install esphome==2026.10.0
esphome run jardinerito.yaml        # first time: USB-C cable. After that it can update over Wi-Fi.
```

Pins: pump = GPIO2, soil sensor = GPIO1 (Grove port). Screen SPI: CLK 15, MOSI 21, CS 14, DC 42, RST 48. The backlight is an LP5562 on I2C (SDA 45, SCL 0, address 0x30). Button = GPIO41.

It also shows up automatically in Home Assistant if you use it.

Made with love for Maria's birthday 🎂
