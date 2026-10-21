# 02 — Who controls what

**The most expensive mistake on this unit, made several times: attacking the wrong layer.**
Some subsystems are plain Android. Others look like Android but are owned by a proprietary
vendor layer (Qianfeng's framework talking to the MCU over UART). The Android API "works"
(no exception) and does nothing.

| Subsystem | Who's really in charge | How to talk to it | Not this |
|---|---|---|---|
| **Bluetooth** (calls, pairing) | Proprietary **GOC daemon** `gocsdk_zj` | AT commands over `/dev/goc_serial` (115200, `\r\n`); unix sockets `goc_control`, `goc_data`, `goc_rfcom`, `goc_spp`. Paired devices in `/data/goc/bt_conf.ini` | Android Bluetooth APIs (cosmetic) |
| **FM/AM radio** | **The MCU** | binder `mcu_service`, command family `0xA0` → [07](07-radio.md) | `RadioManager` / BroadcastRadio HAL. The SoC's own FM tuner is running, but it isn't wired to the car antenna |
| **Volume** | **The MCU** | `android.qf.os.VolumeManager` / binder `qfaudio` → [08](08-volume.md) | `AudioManager.setStreamVolume`, `input keyevent VOLUME_*` |
| **Which app is HOME** | **`car.config`** | `/great/protect_dir/car.config`, or the vendor broadcast → [03](03-car-config.md) | `cmd package set-home-activity`, `setprop persist.sys.qf.launcher` |
| **Standby time** | **`car.config`** | `sleep_time_set` line → [03](03-car-config.md) | `setprop persist.sys.qf.sleep_time` alone |
| **Killing background apps** | `com.qf.carsettings` `KillApps` **and** `QFSleepWakeup` in `framework.jar` | Two whitelist files → [05](05-app-killers.md) | Battery optimisation settings, `lmkd` tuning |
| **Steering wheel keys** | MCU → `com.qf.framework` → `InputManager.injectInputEvent` | Normal `onKeyDown` in your Activity | — |
| **Handbrake, headlights, reverse, ACC** | MCU | `IVehicleTool` callbacks from the vendor client SDK, or `mcu_service` listener → [06](06-mcu-protocol.md) | — |
| Audio routing | Android | `AudioManager` | — |
| GPS | Android (the cleanest subsystem) | `LocationManager` | — |
| Brightness | Android | `Settings.System.screen_brightness` moves the real backlight | — |

**The rule:** before implementing something with an Android API, check whether the vendor
owns it on this unit. The fastest way is to find the vendor app that already does it and
decompile it. That's how the radio protocol, `KillApps` and the volume path were found.

## How the layers stack

```
 your app
   │  onKeyDown            │ mcu_service (binder)        │ android.qf.* classes (reflection)
   ▼                       ▼                             ▼
 com.qf.framework  (system uid)  — owns /dev/ttyS0
   │  UART 115200 8N1, frames FF FD FE … / FF FE FD …
   ▼
 MCU (vendor microcontroller): wheel keys, lights, handbrake, reverse, ACC, battery voltage,
   │                             FM tuner, volume, CAN box link
   ▼
 CAN box (Hiworld, 38400 baud) → car buses
```

The SoC never sees the CAN bus directly; it only gets what the MCU forwards.

## Calling vendor classes from your app

The vendor added classes to `framework.jar` (`android.qf.mcu.McuManager`,
`android.qf.os.VolumeManager`, …). They exist at runtime but not in the SDK you compile
against. Two options:

- **Reflection** (what the working code here does). `ctx.getSystemService("mcu_service")`
  returns the vendor `McuManager` object directly.
- `compileOnly` against a copy of the unit's `framework.jar`. Not tried.

Vendor listener interfaces are plain Java interfaces (not AIDL), so you can implement them
with `java.lang.reflect.Proxy`. Implement `hashCode`/`equals`/`toString` in the handler:
`McuManager` stores listeners in a `HashMap`, and a proxy returning `null` for `hashCode`
crashes with *"Expected to unbox a 'int' primitive type but was returned null"*.
