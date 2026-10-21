# 06 — MCU protocol

The MCU is the vendor microcontroller that reads the steering wheel keys, headlights,
handbrake, reverse gear, ACC and battery voltage, runs the FM tuner and the volume, and talks
to the CAN box. Android talks to it over a UART owned by `com.qf.framework`.

Sources: decompiled `QF_Framework.apk` (`McuManagerService`, `McuConstant`), and frames
captured in logcat on the tested unit. Marked **[verified]** when a real frame confirmed it.

## Transport

- `/dev/ttyS0`, 115200 8N1, held open by `com.qf.framework` (system uid). Confirmed through
  `/proc/<pid>/fd`.
- Other QF platforms (6125, 8581, 7861…) use a different port; `QFApi.getCustomPlatform()`
  picks it. On this unit it falls through to the default.
- Apps should **not** open the UART. Use the `mcu_service` binder.

## Frames

**MCU → app**, header `FF FE FD`:

```
 FF FE FD | LEN | TYPE | CMD | DATA… | CHK | FF
```

`CHK` = XOR of bytes 4 … n−3 (`isValidCheckSum`).

Real example **[verified]**: `FF FE FD 03 01 29 78 50 FF` → CMD `0x29` (41) = battery voltage,
raw value `0x78`; `01 ^ 29 ^ 78 = 50` ✔. The scale to volts is unknown; measure against a
multimeter before converting.

**App → MCU**, header `FF FD FE`, same checksum:

```
 FF FD FE | LEN | 01 | 40 | 5A A5 … (payload) | CHK | FF          CMD 0x40 = ARM2MCU_CANBUS
```

Real example **[verified]**: `FF FD FE 0A 01 40 5A A5 03 60 05 01 32 9A 71 FF`. The inner
`5A A5 …` payload is a Hiworld CAN box frame and has its own last byte = sum of its bytes
mod 256 (`5A+A5+03+60+05+01+32 = 0x19A → 9A`) ✔.

## Command catalog (decimal ids, from `McuConstant`)

| Direction | Id | Name | Content |
|---|---|---|---|
| MCU → app | 32 | `MCU2ARM_KEYCODE` | Key pressed (wheel / panel) |
| MCU → app | 33 | `MCU2ARM_TUNER` | Tuner |
| MCU → app | 34 | `MCU2ARM_HEADLIGHT` | Headlights |
| MCU → app | 35 | `MCU2ARM_HANDBRAKE` | Handbrake |
| MCU → app | 36 | `MCU2ARM_ACC_STATUS` | Ignition (ACC) |
| MCU → app | 37 | `MCU2ARM_VERSION` | MCU firmware version |
| MCU → app | 39 | `MCU2ARM_KEYCODE_EXT` | Extended key |
| MCU → app | 40 | `MCU2ARM_BACKCAR` | Reverse gear |
| MCU → app | 41 | `MCU2ARM_BATTERY_VOLTAGE` | Battery voltage **[verified]**, every ~2 s |
| MCU → app | 42 | `MCU2ARM_SCREEN_STATUS` | Screen on/off |
| MCU → app | 65 | `MCU2ARM_CANBUS` | CAN box reply forwarded by the MCU |
| App → MCU | 64 | `ARM2MCU_CANBUS` | CAN box request (sent by `QF_Canbus`) |
| App → MCU | 16–26, 48–51, 134–135 | Android status, audio, lights, 360 camera, update… | Control |
| App → MCU | 0xA0–0xA2 | Tuner | → [07](07-radio.md) |

> ⚠️ **Never send** 17 (`ARM2MCU_POWEROFF`), 18 (`ARM2MCU_RECOVERY`), 48 / 51
> (`ARM2MCU_UPGRADE_START` / `_END`, MCU firmware update), or the `SET_CAN_UART_BPS` system
> setting. Develop CAN requests (64) read-only.

## From an app

`ctx.getSystemService("mcu_service")` returns the vendor `android.qf.mcu.McuManager`.
The two methods used by the working radio code:

```
McuManager.RPC_SendMcuMsgData(byte cmd, byte[] data, int len)
McuManager.RPC_RequestMcuInfoChangedListener(McuListener l)   // l.onMcuInfoChanged(byte[] data)
```

`data[0]` in the listener is the command id. Before the MCU accepts commands from a package,
the vendor SDK registers the package name with binder **transaction 1001** on `mcu_service`
(interface token, then the package name as a string). See
[`examples/radio/McuRadioControl.kt`](../examples/radio/McuRadioControl.kt) for all of this
done by reflection.

Higher-level callbacks for handbrake and headlights exist in the vendor client SDK
(`com.qf.clientsdk.QFVehicleManager.registerVehicleTool(IVehicleTool)` with `onHandBrake`,
`onHeadLightChange`). Not tried from a third-party app.

## Steering wheel keys

The MCU sends the key, `com.qf.framework` injects it with `InputManager.injectInputEvent`,
and your Activity gets a normal `KeyEvent` in `onKeyDown`. Key codes depend on the vendor key
learning (`QF_KeyStudy`); log them with `adb logcat | grep -iE 'keycode|KeyEvent'` while
pressing each button. Volume keys are swallowed by QF (`QFKeyEvent: ignore key(KEYCODE_VOLUME_UP)`).

## The CAN box (Hiworld)

The CAN box configuration is in `/great/canconf/canconfig.xml`. On the tested car: brand
Chevrolet, type Captiva, version `captiva_08_all`, provider **`canprovider_hiworld_5aa5`**,
parser `com.qf.vehicle.band.gm.parse.wc.GmDataController`. Line speed 38400.

Data types handled by the GM parser in `QF_Canbus.apk` (`GmDataParser`, field `dataType`):

| Type | Parser | Content |
|---|---|---|
| 17, 18, 19 | `parseCentralState` | Central state (by subtype) |
| 33 | `parsePanelKey` | Panel keys |
| 34 | `parseKnob` | Rotary knob |
| 49 | `parseAcState` | Climate: power, fan, temperature, recirculation |
| **50** | `parseCarBodyState` | **Engine rpm, instant speed, consumption** |
| 52 | `parseOilMileageInfo` | Average consumption and range |
| 53, 69, 70, 85, 117 | `parseCentralState` | Doors, windows, lights… |
| 65 | `parseRadarState` | Parking sensors |
| 86 | `parseSteeringWheelKey` | Wheel keys (subtypes 17/18/19) |
| −16 | `parseCanboxVersion` | CAN box version |

Observed rhythm: the vendor polls `5A A5 03 60…` every ~1 s and `5A A5 02 24…` every ~3 s.
**Unknown:** what `0x60` and `0x24` mean, and whether type 50 (rpm/speed) actually arrives on
this car. A 20 s capture with the engine running showed only CMD 41. It's a negative from one
window, not conclusive.
