# 05 — Why your apps die

Symptoms on the tested unit, all with the same root cause:

- Background services (VPN, data loggers, your launcher's overlays) vanish after a few
  seconds in the background, or after every standby.
- After waking from standby, the custom launcher's overlays are gone and you see black bands
  around the foreground app.
- Z-Link (CarPlay / Android Auto) connects fast at ignition and then **drops about 70 seconds
  later**, then reconnects by itself.

It isn't `lmkd`, Doze or battery optimisation. The ROM has **two app killers**, each with its
own whitelist, and neither reads the other's.

## Killer 1: `KillApps` in `com.qf.carsettings`

Found by decompiling `com.qf.carsettings.utils.KillApps`. When an activity goes to the
background, CarSettings gets `ACTIVITY_CHANGE` and **4 seconds later** walks the recent
tasks: it **keeps the 2 newest** (`MAX_RESERVE_APP = 2`) and does `removeTask` +
`forceStopPackage` on the rest.

Spared:

- the foreground app and the last audio source;
- the apps in the properties `persist.sys.maps`, `persist.sys.dvr.app`, `persist.sys.obd.app`,
  `persist.sys.tpms.app`;
- a fixed `KILL_WHITE_LIST` inside the APK, which **includes `com.zjinnova.zlink`** (that's
  why Z-Link never dies and everything else does);
- **an editable whitelist file:**

```
/great/protect_dir/bg_white_list.config      system:system, 0666, u:object_r:system_data_file:s0
```

One package name per line:

```
com.tailscale.ipn
com.example.launcher
com.example.radio
moe.haruue.wadb
```

## Killer 2: `QFSleepWakeup.killAppsBeforeSleep()` in `framework.jar`

`bg_white_list.config` is not enough. When the ignition goes off,
`android.qf.os.QFSleepWakeup.killAppsBeforeSleep()` force-stops **everything** that's running,
except:

- `system` processes and anything starting with `com.android.launcher3`;
- `/system/config/NotKillAppsBeforeSleep.ini` (fixed list: Z-Link, the factory launchers,
  SystemUI…);
- **`/great/sleep/sleep_whitelist`**, one package per line, matched with `startsWith`.

**That file doesn't exist on a stock unit.** Create it (directory `0755`, file
`system:system`, `0644`, `u:object_r:system_data_file:s0`). It's re-read on every sleep
cycle, no reboot needed.

```bash
adb shell 'mkdir -p /great/sleep && chmod 755 /great/sleep'
adb shell 'printf "%s\n" com.example.launcher com.tailscale.ipn > /great/sleep/sleep_whitelist'
adb shell 'chown system:system /great/sleep/sleep_whitelist; chmod 644 /great/sleep/sleep_whitelist; chcon u:object_r:system_data_file:s0 /great/sleep/sleep_whitelist'
```

[`scripts/apply-settings.sh`](../scripts/apply-settings.sh) writes both files.

## Case study: the VPN that kills Z-Link

The complaint was literally "Z-Link connects super fast, but then Tailscale starts while
Z-Link is active and I lose the connection to my phone". The event log says exactly that:

```
15:36:27  am_kill  [com.tailscale.ipn, 200, "stop com.tailscale.ipn"]   ← KillApps, at parking
15:36:41  power_sleep_requested
22:22:19  (wake) com.zjinnova.zlink resume → re-attaches the phone
22:23:30  am_proc_start com.tailscale.ipn / IPNService                  ← +71 s
```

The VPN created at 22:23:30 is **new** (`dumpsys connectivity` shows `reason: agentConnect`)
and covers uid ranges `{0-10106, 10108-99999}`: every app except Android Auto, the one package
the Tailscale client always excludes. **When a new VPN comes up, Android tears down the
connections of every app in its uid range** so they reconnect through the tunnel. Z-Link is in
the range. Hence the drop ~70 s after starting the car, just as music started playing.

Fixes, in layers:

1. VPN app in **both** whitelists → its process survives parking → the tunnel is still up on
   wake → no new VPN → nothing gets torn down.
2. Exclude Z-Link from the VPN (Tailscale → Settings → App split tunneling →
   `com.zjinnova.zlink`). Verified in `dumpsys connectivity`: the VPN range then skips Z-Link's
   uid. Even if the tunnel restarts, Z-Link isn't affected.
3. If you start the VPN from a root script, use the app's official intent, **not**
   `am start-foreground-service` on its service:
   ```bash
   am broadcast -a com.tailscale.ipn.CONNECT_VPN -n com.tailscale.ipn/.IPNReceiver
   ```
   Pushing `IPNService` directly caused an ANR ("`startForegroundService()` did not then call
   `startForeground()`") → crash → `am_proc_bad`, and **Android refused to start Tailscale for
   3½ hours**. Sending `CONNECT_VPN` while the tunnel is already up doesn't create a new VPN
   (same `network{}` id before and after), so it's safe to send on every wake.

## Detecting wake from standby in a script

There's no reliable broadcast for "woke up from standby" that a root shell script can wait on,
and alarms don't wake the unit (see [10](10-other-traps.md#alarms-never-wake-the-unit)). What
works: a loop that `sleep`s a few seconds and compares wall-clock time. `sleep` doesn't run
while suspended, so a jump much larger than the interval means the unit just woke up.

```sh
prev=$(date +%s)
while true; do
  sleep 3
  now=$(date +%s)
  if [ $((now - prev)) -gt 30 ]; then
    echo "woke from standby"          # re-start things here
  fi
  prev=$now
done
```

## Keeping your own service alive

With both whitelists in place, the remaining risk is a crash. A tiny root watchdog started by
init (an `.rc` file in `/system/etc/init/` running a shell loop) that relaunches your
service if `pidof` doesn't find it has been reliable. As root you can even
`am start-foreground-service` a **non-exported** service of your own app, which an app can't
do.
