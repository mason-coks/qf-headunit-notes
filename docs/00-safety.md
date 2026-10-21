# 00 — Safety

These head units give you root over ADB and a writable `/system`. There is no "are you sure?"
anywhere. Rules that kept the tested unit alive:

## Things that can brick the unit or the car's audio

| Don't | Why |
|---|---|
| Send MCU commands you don't understand | The MCU catalog includes power-off (17), recovery (18) and **MCU firmware update** (48 / 51). A bad update can leave the car without screen or radio. `SET_CAN_UART_BPS` changes the CAN box baud rate and cuts the link to the car. See [06](06-mcu-protocol.md) |
| Write to `/dev/block/*` or `/persist` | Boot and calibration data |
| Edit files in `/great/` without a backup | `/great` holds `car.config` and the vendor's whitelists. A broken `car.config` can leave the unit with no HOME app |
| Disable `com.android.systemui` | It's a persistent app and gets restarted anyway, and you can end up with no system UI |
| Add a privileged permission to an app in `/system/priv-app` | `ro.control_privapp_permissions=enforce`: a privileged permission not listed in `/etc/permissions/privapp-permissions-*.xml` **stops the unit from booting** |
| Leave a backup file inside `/system/etc/init/` | init parses **every** file in that directory, `.bak` included, and defines the service twice |
| Add iptables rules over a remote connection | On one attempt the ACCEPT rule used the interface `tailscale0`, which doesn't exist on Android (the tunnel is `tun0`/`tun1`). The unit became unreachable over IPv4. It was recovered over IPv6 only because iptables rules are IPv4-only |
| Fill `/` | The root filesystem ships at 100 % (≈7 MB free). Put your APKs in `/data`, not `/system`, unless you must replace a system component |
| Flash anything | The bootloader is locked with AVB green state. Nothing to flash, nothing to gain |

## How to keep everything reversible

1. Before overwriting a file, copy it next to a dated name **outside** directories that are
   parsed (`/data/local/tmp/backups/` is a good place):
   ```bash
   adb shell mkdir -p /data/local/tmp/backups
   adb shell cp /great/protect_dir/car.config /data/local/tmp/backups/car.config.$(date +%Y%m%d)
   ```
2. Preserve owner, mode and SELinux context when you put a file back. For the files in
   `/great/protect_dir/` that's `system:system` and `u:object_r:system_data_file:s0`:
   ```bash
   adb shell chown system:system <file>
   adb shell chmod 600 <file>          # car.config is 600; bg_white_list.config is 666
   adb shell chcon u:object_r:system_data_file:s0 <file>
   ```
3. Changes to `/system` need `adb remount` first. `/system` comes up read-only on every boot.
4. If you patch a framework jar, install a boot counter that restores the original
   automatically after 3 failed boots. See [09](09-app-frame-hook.md#the-safety-net).
5. Test what you can in an emulator (Android 10, API 29, 768×1024 @160 dpi) first. The
   emulator has no MCU, so design your app with a fake data source.

## Driving

Don't test anything that makes you look at the screen while the car is moving.
