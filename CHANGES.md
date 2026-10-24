# Changes

Changes made to `jardinerito.yaml` while building it for the first time (ESPHome 2026.10.0).

## 1. ntfy header lambdas: compile error fix

`esphome compile` failed:

```
jardinerito.yaml:511:14: error: cannot convert 'std::string' to 'const char*' in return
jardinerito.yaml:512:14: error: cannot convert 'std::string' to 'const char*' in return
```

In ESPHome 2026.10, `http_request` `request_headers` lambdas must return `const char *`.
`return title.c_str();` would leave a dangling pointer: the lambda receives the script
parameters by value, so the copy is freed when the lambda returns, and the header is sent later.
The value is now copied into a `static std::string` and that pointer is returned. It stays valid
while the request is sent, and the `notify` script is `mode: queued`, so requests never overlap.

```yaml
# before
Title: !lambda return title;
Tags: !lambda return tags;
# after
Title: !lambda "static std::string v; v = title; return v.c_str();"
Tags: !lambda "static std::string v; v = tags; return v.c_str();"
```

## 2. OTA password moved to `secrets.yaml`

The OTA password was hardcoded in the YAML. It is now `password: !secret ota_password`.
`secrets.yaml` is git-ignored. The password value was also changed (old project name → `jardinerito`);
the device was re-flashed over USB with the new one.
To build this yourself, create `secrets.yaml` next to the YAML:

```yaml
ota_password: "choose-a-password"
```

The setup hotspot password `plantlove` stays in the YAML on purpose. It is the documented
first-time setup password (see README).

Changes 1-2 did not touch pins, watering/safety logic, timings or display settings.

## 3. Spanish screens (to match `docs/*.gif`)

Requested by the owner: the screen now matches the Spanish gifs in `docs/`.
- All screen text in Spanish ("¡Olé! Humedad 62%", "¡Tengo sed!", "¡Glu, glu, glu!", "¡Agua, por favor!",
  info page, "¡Calíbrame!"). Fonts get the extra glyphs `¡¿áéíóúñÁÉÍÓÚÑü`.
- New decorations: sun + red flower when happy, wilted flower with falling petal when thirsty / jar empty,
  sweat drop (thirsty), tear (jar empty), drops from the sky while drinking.
- New "Siesta" night screen (22:00-07:00, same rule as the existing backlight dimming; a button press wakes it).
  Not shown while drinking or when the jar is empty.
- Birthday screen: "¡Feliz cumpleaños, María!" with a Spanish-flag cake. `birthday_name` is now `María`.
- Display `update_interval` 500ms -> 200ms so the animations are smooth. Logs show no slow-loop warnings.

Watering logic, safety limits, pins, and the display model are unchanged. The web settings page stays in English.

## 4. Calibration buttons renamed

"Calibrate DRY (sensor in air)" / "Calibrate WET (sensor in water)" are now "Calibrate DRY" / "Calibrate WET".
Calibration is now done in the plant's pot: dry soil, then right after a good watering. The old labels
would have said the opposite on the settings page. `setup.sh` uses the new names, so a device with older
firmware needs `./setup.sh flash` once.
