# Qianfeng (QF) Android head unit notes — K706 / UIS7862S

Field notes from several months of taking apart a cheap Chinese Android car head unit: what the
vendor layer actually controls, where the real settings live, why apps keep dying, how to get
rid of the system bars, how to drive the FM radio and the volume from your own app, and the
one `services.jar` hook needed to fit apps into a custom launcher.

Everything here was **measured on a real unit installed in a car**. Things that are inferred
or untested are marked as such. The dead ends are documented as carefully as the solutions,
because most of them look like the obvious way to do it.

> [!WARNING]
> These units ship with **root ADB** and a writable `/system`. That makes everything below
> possible, and it also makes it easy to leave the unit without a launcher, without system UI
> or unable to boot. Read [`docs/00-safety.md`](docs/00-safety.md) first. No warranty: you do
> this at your own risk, on your own car.

## Is your unit the same?

The notes apply directly if your unit looks like this:

| | Unit tested |
|---|---|
| Model string | `ROCO/K706/K706:10/QP1A.190711.020` |
| ROM | Qianfeng, build `QF001.20250408.*`, all vendor packages named `com.qf.*` / `QF_*.apk` |
| SoC | Unisoc **UIS7862S** (`ro.board.platform=ums512`, `ro.hardware=uis7862s_1h10`) |
| Android | **10** (API 29), security patch 2020-06-05 (sold as "Android 14") |
| RAM / storage | 6 GB / ~58 GB eMMC |
| Screen | 768×1024 portrait panel at 160 dpi |
| Phone projection | Z-Link (`com.zjinnova.zlink`) for CarPlay / Android Auto |
| CAN box | Hiworld (`canprovider_hiworld_5aa5`) |

Quick check over ADB:

```bash
adb shell getprop ro.build.fingerprint
adb shell service list | grep -E 'mcu_service|qfaudio'
adb shell ls /great/protect_dir/
```

If you have `mcu_service`, `qfaudio` and a `/great/protect_dir/car.config`, you have a QF ROM
and most of this applies, even on a different SoC or model name. Other Unisoc/QF units sold
as T610, T618, 7862 or 8581 share the same framework; the details (offsets in `services.jar`,
screen size) will differ.

## Contents

| Doc | What you get |
|---|---|
| [00 — Safety](docs/00-safety.md) | What can brick the unit, how to make every change reversible |
| [01 — Device and access](docs/01-device-and-access.md) | Root ADB out of the box, `adb remount`, why there is no custom ROM (and why you don't need one) |
| [02 — Who controls what](docs/02-who-controls-what.md) | **Read this first.** Bluetooth, radio, volume, HOME and app killing are vendor layers, not Android |
| [03 — `car.config`](docs/03-car-config.md) | The real settings store: default launcher, standby time, and why `setprop` doesn't stick |
| [04 — Fullscreen and system bars](docs/04-fullscreen-and-bars.md) | Two different problems; the overscan trick; four things that don't work |
| [05 — Why your apps die](docs/05-app-killers.md) | The two app killers (`KillApps` and `QFSleepWakeup`) and their whitelists; the VPN that drops Z-Link |
| [06 — MCU protocol](docs/06-mcu-protocol.md) | UART framing, command catalog, Hiworld CAN data types |
| [07 — FM radio](docs/07-radio.md) | The radio hangs off the MCU, not `RadioManager`. Full command set + working Kotlin |
| [08 — Volume](docs/08-volume.md) | All Android streams are stuck at 9; the MCU owns volume. How to set it |
| [09 — Fitting apps into a launcher](docs/09-app-frame-hook.md) | A 4-line `services.jar` hook with a boot-loop rescue; per-app density |
| [10 — Other traps](docs/10-other-traps.md) | Alarms never wake the unit, Chinese A-GPS server, notification listener, init `.bak` files… |

| Folder | |
|---|---|
| [`scripts/`](scripts/) | Read-only info collector, and apply/revert scripts for the settings (dry run by default) |
| [`hooks/`](hooks/) | Smali/Java sources and diffs for the `services.jar` hooks. **No vendor binaries** |
| [`examples/radio/`](examples/radio/) | The Kotlin class that drives the FM tuner through `mcu_service` |

## What is not here

- **Vendor APKs, jars or decompiled vendor source.** They are copyrighted. Protocol tables
  and API names are documented in prose; you can decompile your own unit's
  `QF_Framework.apk` with [jadx](https://github.com/skylot/jadx) to follow along.
- The custom launcher itself (it depends on everything below plus car-specific hardware).
- The car side (CAN decoding for a Chevrolet Captiva, an ESP32 gateway). That's another story.

## Contributing

If your unit behaves differently, open an issue with `getprop ro.build.fingerprint`, the
output of [`scripts/collect-info.sh`](scripts/collect-info.sh) (review it before posting: it
contains your settings) and what you observed. Corrections with evidence are very welcome.

## License

Documentation: [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
Scripts and code: MIT. See [LICENSE](LICENSE).

Spanish summary: [README.es.md](README.es.md).
