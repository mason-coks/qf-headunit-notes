# 07 — FM radio

## The radio is not Android's radio

There is a `vendor.sprd.hardware.broadcastradio@2.0-service` running, and `RadioManager`
finds a tuner. **That's the SoC's own FM receiver, and it isn't wired to the car antenna.**
The factory radio app (`QF_FMRadioExt.apk`, package `com.android.fmradio.ext`) never touches
`RadioManager`. It talks to the **MCU** through `mcu_service`, using the vendor client SDK
(`com.qf.clientsdk.QFTunerManager`), which is bundled inside the APK.

Everything below was verified in the car: seek sweeping the dial live, preset recall, reading
the real presets, live frequency and signal.

## Commands (app → MCU)

Sent with `McuManager.RPC_SendMcuMsgData(cmd, data, len)`.

| Cmd | Name | |
|---|---|---|
| **`0xA0`** | `CMD_ARM2MCU_TUNER_SETTING_TUNE` | Tuner orders, `data = [sub, p1, p2]` |
| `0xA1` | `CMD_ARM2MCU_TUNER_SETTING_PRESET_LIST` | Load a preset list |
| `0xA2` | `CMD_ARM2MCU_TUNER_SETTING_RDS` | `[v]` global RDS on/off |

Subcommands of `0xA0`:

| Sub | Action | Params |
|---|---|---|
| `0x00` | **Tune to frequency** | `p1,p2` = frequency, big-endian, in dial units (FM: tens of kHz, 94.85 MHz → 9485; AM: kHz) |
| `0x01` | Seek up | — |
| `0x02` | Seek down | — |
| `0x03` | Step up (one 0.05 MHz step on FM) | — |
| `0x04` | Step down | — |
| `0x05` | Start scan | — |
| `0x06` | **Switch band** (FM/AM) | `p1` = band (AM untested) |
| `0x07` | Local / distant sensitivity | `p1` |
| `0x08` | **Auto-store**: seek and save presets | — |
| `0x09` | Preset scan | — |
| `0x0A` | Dial region (Europe / US / Japan) | `p1` |
| `0x0B` | **Save current station** to a preset | `p1` = preset number (1-based) |
| `0x0C` | Stop scan | — |
| `0x0D` | **Recall preset** | `p1` = preset number (1-based) |
| `0x0E` / `0x0F` | Next / previous (wheel keys) | — |
| `0x10` | Stereo / mono | `p1` |
| `0x11` | Toggle RDS AF | — |
| `0x12` | Toggle RDS TA (traffic) | — |
| `0x13` | Toggle RDS REG | — |
| `0x14` | Toggle RDS EON | — |
| `0x15` | **Filter by RDS PTY category** | `p1` = programme type |

Extended tune, setting band and region in the same command:
`[0xA0, 0x00, (band << 4) | region, freq_hi, freq_lo]`.

Watch out: the vendor SDK booleans are backwards. `onSeek(true)` sends seek **down**,
`onFine(true)` sends step **down**.

## Replies (MCU → app)

Arrive in `McuListener.onMcuInfoChanged(byte[])`, `data[0]` = code.

| Code | Name | Content |
|---|---|---|
| `0xB0` | `TUNER_INFO` | Tuner state. Seen on the unit: `B0 58` = signal quality 0x58 = 88/100 **[verified]** |
| `0xB1` | `PRESET_LIST_INFO` | Band, current frequency and the 6 presets **[verified]**, see below |
| `0xB2` | `FREQ_RANG_INFO` | Dial limits and step for the band |
| `0xB3` | `TUNER_RDS_INFO` | Generic RDS |
| `0xB4` | `RDS_INDICATE_INFO` | TA / AF / TP indicators |
| `0xB5` | `RDS_PTY_TYPE_INFO` | PTY category of the current station |
| `0xB6` | `RDS_PS_INFO` | Station name (PS), ASCII after the code byte (parser written, no frame seen yet) |
| `0xB7` | `RDS_RT_INFO` | Radiotext |
| `0xB8` | `RDS_PS_PRESET_LIST_INFO` | PS names of the presets |

A real `0xB1` frame from the car:

```
B1 00 00 | 25 0D | 22 60 22 B0 23 32 24 AE 24 F4 25 C6
└code    └band   └freq   └─────────── 6 presets ──────────┘
```

`0x250D` = 9485 → 94.85 MHz. The presets decode to 88.00 / 88.80 / 90.10 / 93.90 / 94.60 /
96.70, exactly what the factory app showed.

The MCU only reports **when something changes**, not periodically. Persist the last known
state in your app, or it will show invented values until the user touches something.

## Working code

[`examples/radio/McuRadioControl.kt`](../examples/radio/McuRadioControl.kt) does all of this
by reflection: registers the package with the MCU (binder transaction 1001), sends the
commands, implements `McuListener` with a `Proxy`, and parses `B0`, `B1`, `B6`.

## Replacing the factory radio

The radio button on the vendor top bar sends an **explicit** intent to
`com.android.fmradio.ext/com.android.fmradio.FmMainActivity`. An explicit intent can't be
intercepted with an intent filter, so the only way to have your app open from that button is
to **be** that component: same `applicationId` and the same activity class name, installed in
place of `/system/priv-app/QF_FMRadioExt/QF_FMRadioExt.apk` (keep the original as a backup
**outside** that directory or with a non-`.apk` name).

Two constraints:

- `ro.control_privapp_permissions=enforce`. The privileged permissions whitelisted for that
  package on the tested unit were `MOUNT_UNMOUNT_FILESYSTEMS`, `ACCESS_FM_RADIO`,
  `MODIFY_AUDIO_ROUTING`, `ACCESS_BROADCAST_RADIO`, `CHANGE_CONFIGURATION`, `MANAGE_USERS`,
  `SET_MEDIA_KEY_LISTENER`. **Asking for any other privileged permission stops the unit from
  booting.** Check your unit's `/etc/permissions/privapp-permissions-*.xml`.
- After the first install in `/system/priv-app`, updates can go through `adb install -r` as
  long as the signing key doesn't change.

## Audio

The FM audio is routed by the MCU/codec, not played by Android. Your app only sends commands
and shows state. `AudioRecord` on `AUDIO_DEVICE_IN_FM_TUNER` initialises, but in tests the
samples came back silent; untested with the radio actually playing.

Also: R8 strips `Log.d` calls in release builds. If you need to see what you send to the MCU
in the car, log with `Log.i`.
