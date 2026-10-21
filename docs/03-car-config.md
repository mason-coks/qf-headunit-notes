# 03 — `car.config`: the real settings store

On this ROM a handful of settings **look** like Android properties, but the property is only a
copy. The source of truth is a text file on the vendor partition:

```
/great/protect_dir/car.config      owner system:system, mode 600, context u:object_r:system_data_file:s0
```

The QF framework reads it at boot and **rewrites** the matching properties from it. So
`setprop` "works" until the next reboot and then silently reverts.

**If a setting doesn't survive a reboot, look in `car.config` first.**

## Format

One setting per line, tab-separated fields:

```
# name=,    default=,   current=,   values=,    visible=,   restore=,   reset=
name=navi_default_app,  default=com.google.android.apps.maps,  current=com.waze,  values=com.google.android.apps.maps,  visible=1,  restore=0,  reset=1
name=default_volume,    default=12,  current=5,   values=0 32,  visible=1,  restore=0,  reset=1
name=navi_volume,       default=9,   current=10,  values=0 15,  visible=1,  restore=0,  reset=1
name=voice_wakeup_word, default=你好小车, current=你好小车, values=你好小车, visible=0, restore=0, reset=1
```

Other entries seen: `navi_boot_start`, `navi_remix`/`navi_remix_ratio` (navigation audio
ducking), `phone_volume`, `radio_volume`, `aux_volume`, `speed_volume_control`, `headlight`,
`buzzer`, `float_ball`, `float_navi_bar`, `backcar_func`, `backcar_mute`, `backcar_ruler`,
`dvr_default_app`, `brake`, `launcher_default_app`, `sleep_time_set`.

Edit it with a backup, then restore owner, mode and context:

```bash
adb shell cp /great/protect_dir/car.config /data/local/tmp/backups/car.config.$(date +%Y%m%d)
adb pull /great/protect_dir/car.config
# edit locally, keeping tabs
adb push car.config /data/local/tmp/car.config.new
adb shell 'cat /data/local/tmp/car.config.new > /great/protect_dir/car.config'   # keeps owner/context
adb shell 'chown system:system /great/protect_dir/car.config; chmod 600 /great/protect_dir/car.config; chcon u:object_r:system_data_file:s0 /great/protect_dir/car.config'
```

## Default launcher (HOME)

| What you'd try | What happens |
|---|---|
| `cmd package set-home-activity <pkg>/<activity>` | `resolve-activity` shows your launcher… and it makes no difference |
| `setprop persist.sys.qf.launcher <pkg>` | Rewritten from `car.config` on every boot |

**What works**, two ways:

1. The broadcast the vendor Settings app uses. It stops the old launcher, sets the property
   and rewrites `car.config` for you:
   ```bash
   adb shell am broadcast -a com.qf.action.SET_LAUNCHER --es packageName com.example.launcher
   ```
2. Edit the `launcher_default_app` line by hand: set `current=` to your package **and** append
   it to `values=`.

The factory launcher on the tested unit is `com.android.launcher.horizon.city`. Leave it
installed as a fallback. Other apps that declare a HOME intent filter (old dashboards, etc.)
are best disabled with `pm disable-user` so the vendor can't pick them.

## Standby time

`persist.sys.qf.sleep_time` is **not hours, it's an index** into a table hard-coded in
`CarSettingService.setSleepTime()` (`com.qf.carsettings`):

| Index | Standby after ignition off |
|---|---|
| 0 | Never sleeps (keeps draining) |
| 1 | 2 hours (what the tested unit came with) |
| 2 | 1 day (the `default=` value in `car.config`) |
| 3 | 3 days |
| 4 | 7 days |

It's sent to the MCU (`RPC_SendMcuMsgData(0x18, [0x0D, hours])`) only from
`initMcuManager()`. So:

- Changing it from the vendor menu ("Sleep time") applies at once.
- `setprop` needs a reboot **and** gets overwritten from `car.config` at boot. To make it
  permanent, set `current=` on the `sleep_time_set` line.

Measured during a 54-minute stop: the unit really suspends to RAM, and USB loses power while
asleep (a device on the USB port reboots on wake). Bluetooth stays on with ignition off
(`sys.qf.is.bt.on.when.accoff=true`).
