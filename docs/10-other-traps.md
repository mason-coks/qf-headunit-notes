# 10 — Other traps

Short ones, each of which cost at least an evening.

## Alarms never wake the unit

The factory `AlarmManagerService.setImpl()` (in `services.jar`) rewrites **every**
`RTC_WAKEUP` to `RTC` and `ELAPSED_REALTIME_WAKEUP` to `ELAPSED_REALTIME`, for every app.
Anything you schedule "for while it sleeps" fires all at once when the ignition comes back.
To do something on wake, detect the wall-clock jump from a root script (see
[05](05-app-killers.md#detecting-wake-from-standby-in-a-script)).

## The A-GPS server is in China, and there are two copies of the config

`/vendor/etc/supl.xml` points to `supl.qxwz.com`. Changing it isn't enough: the GNSS stack
keeps its own copy in `/data/vendor/gnss/supl/supl.xml`, rewritten at each boot, and that's
the one it uses. Change both (e.g. to `supl.google.com`, port 7275). Whether the `/data` copy
stays changed after the GNSS service restarts is still unverified.

(Separate issue on the tested unit: 0 satellites in view in 1h22m of driving. All positions
came from the mobile network. Main suspect: the GPS antenna connector behind the unit.)

## Reading media sessions (to show what Z-Link is playing)

`settings put secure enabled_notification_listeners …` is not enough:
`MediaSessionManager.getActiveSessions()` keeps throwing
`SecurityException: Missing permission to control media`. What works:

```bash
adb shell cmd notification allow_listener com.example.launcher/com.example.launcher.MediaListener
```

## Overlay permissions for a launcher

```bash
adb shell appops set com.example.launcher SYSTEM_ALERT_WINDOW allow
adb shell appops set com.example.launcher WRITE_SETTINGS allow
adb shell pm grant com.example.launcher android.permission.WRITE_SECURE_SETTINGS
```

## Starting a VPN app from a root script

Use the app's own intent (for Tailscale, `am broadcast -a com.tailscale.ipn.CONNECT_VPN -n
com.tailscale.ipn/.IPNReceiver`), never `am start-foreground-service` on its service. Details
in [05](05-app-killers.md).

## A USB device re-enumerated on wake doesn't error, it goes quiet

After standby the unit re-enumerates USB devices (`/dev/bus/usb/001/003` → `…/013`). An app
holding the old file descriptor (`ls -l /proc/<pid>/fd` shows it as `(deleted)`) gets `-1`
from `bulkTransfer` forever: no exception, no log, frozen data and a loop burning CPU. Check
that your device is still in `UsbManager.getDeviceList()` and reopen it when it goes quiet.
And make the UI say when its data isn't live.

## init parses every file in `/system/etc/init/`

A `myservice.rc.bak` next to `myservice.rc` defines the service twice. Keep backups
elsewhere.

## `Log.d` disappears in release builds

R8 strips `Log.d`. If you need to read a log in the car, use `Log.i` or higher.

## "It works, but slowly" can be a silent failure

Measure the latency of each link (`date +%s%N` before and after) before blaming the layer
above. See the `inotifyd` story in [09](09-app-frame-hook.md#polishing-it).

## Things that look like the right way and aren't

| What you'd do | Why it doesn't work here | What works |
|---|---|---|
| `cmd package set-home-activity` | `car.config` wins | [03](03-car-config.md) |
| `setprop persist.sys.qf.launcher` | Rewritten at boot from `car.config` | [03](03-car-config.md) |
| `setStreamVolume` / volume keyevents | MCU owns volume | [08](08-volume.md) |
| `RadioManager` | Wrong tuner | [07](07-radio.md) |
| Android Bluetooth APIs | GOC daemon owns BT | [02](02-who-controls-what.md) |
| `enabled_notification_listeners` | Not enough for media sessions | `cmd notification allow_listener` |
| `am start-foreground-service` for a VPN | ANR → process marked bad for hours | The VPN app's intent |
| Freeform windows for a split layout | Forces system bars, breaks Waze | [09](09-app-frame-hook.md) |
| `wm overscan` to confine apps | Only pushes bars off-screen | [09](09-app-frame-hook.md) |
| A custom ROM | Locked bootloader, no AOSP for UIS7862S | Factory root + overlay |
