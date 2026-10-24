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
`secrets.yaml` holds the same value as before and is git-ignored, so the device itself is unchanged.
To build this yourself, create `secrets.yaml` next to the YAML:

```yaml
ota_password: "choose-a-password"
```

The setup hotspot password `plantlove` stays in the YAML on purpose. It is the documented
first-time setup password (see README).

No pins, watering/safety logic, timings or display settings were changed.
