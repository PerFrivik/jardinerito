# Jardinerito 🌱

A little gardener for your plant: it checks the soil, waters from a jar by itself, shows how the plant feels and can message your phone.

| ¡Olé! | ¡Tengo sed! | ¡Glu, glu! | ¡Agua, por favor! | Siesta |
|:---:|:---:|:---:|:---:|:---:|
| ![happy](docs/happy.gif) | ![thirsty](docs/thirsty.gif) | ![drinking](docs/drinking.gif) | ![refill the jar](docs/sad.gif) | ![night](docs/siesta.gif) |
| happy | thirsty | drinking | refill the jar | night |

<p align="center"><img src="docs/birthday.gif" width="200" alt="¡Feliz cumpleaños, María!"></p>

## Setup

Put the plant pot next to your laptop, plug Jardinerito into the laptop with USB-C, then run:

```bash
git clone https://github.com/PerFrivik/jardinerito.git
cd jardinerito
./setup.sh
```

It walks you through it step by step:
1. **Wi-Fi:** type your Wi-Fi name and password. They go to Jardinerito through the cable.
2. **Calibration in the pot:** it measures the soil while it's dry, then again after you water it well.
   This is how it learns when your plant needs water.
3. **Phone notifications** (optional, last): messages when it waters or the jar is empty.

Good to know:
- **Push the sensor into the soil only up to the line printed on it.** The top part isn't waterproof.
- It only waters by itself after calibration, so it can never flood the plant by accident.
- After setup, wait 1 minute before unplugging it. Then any USB-C charger next to the plant will do.
- Watering works without Wi-Fi. New Wi-Fi? Run `./setup.sh wifi`, or join `Jardinerito-Setup` (password `plantlove`) from any phone or laptop.
- Redo a single step any time: `./setup.sh calibrate` or `./setup.sh notify`.

## The button

<p align="center"><img src="docs/buttons.png" width="600" alt="Press once: water now (press again to stop). Press twice: surprise. Hold 2 s: Wi-Fi info and IP address."></p>

Press once to water now (press again to stop). Hold for 2 s to see the address of the settings page.

## How it waters

When the soil is below 35 %, it pumps 3 s, then waits 15 min for the water to spread before checking again. At most 6 times a day, and the pump never runs longer than 15 s.
If watering 3 times in a row doesn't help, the jar is probably empty: refill it and press the button.
At night (22:00 to 07:00) it takes a siesta and the screen dims.

Once `./setup.sh` has run, you can change the moisture level, burst length, soak time and bursts per day
in a browser: hold the button for 2 s to see Jardinerito's address, then open it on any phone or laptop
on the same Wi-Fi. The 15 s pump limit and the night hours are fixed.

**Big plant?** Measure one burst: put the outlet tube in a measuring cup and press the button once. Then set
"Pump burst length" and "Max bursts per day" on the settings page, so a day's bursts cover what the plant drinks
on a hot day. If it ever runs out, it sends a "daily watering limit reached" message.

## Modifying the software

The firmware is [ESPHome](https://esphome.io). Everything (screen drawing, watering logic, settings) is in [`jardinerito.yaml`](jardinerito.yaml).

```bash
./setup.sh flash                      # first time: installs the tools and flashes over USB
. .venv/bin/activate
esphome run jardinerito.yaml          # after that: build and update over Wi-Fi
```

Giving it to someone? `./setup.sh reset` erases its Wi-Fi, calibration and names (the firmware stays), so they can run `./setup.sh` themselves.

`setup.sh` creates `secrets.yaml` with the password for wireless updates. Keep it, it's not in git.

Pins: pump = GPIO2, soil sensor = GPIO1 (Grove port), button = GPIO41. Screen SPI: CLK 15, MOSI 21, CS 14, DC 42, RST 48. Backlight: LP5562 on I2C (SDA 45, SCL 0, address 0x30).

It also shows up automatically in Home Assistant.
