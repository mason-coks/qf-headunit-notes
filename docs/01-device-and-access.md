# 01 — Device and access

## What the unit really is

| | Measured | What the seller / third-party docs said |
|---|---|---|
| SoC | Unisoc UIS7862S (UMS512 family, 8× ARM64, Mali-G52) | "T610" |
| RAM | 6 GB (5.9 GiB `MemTotal`) | "4 GB" |
| Android | 10, API 29, patch 2020-06-05 | "Android 14" |
| Build | `QF001.20250408.135749`, `user/release-keys`, `ro.debuggable=0` | |
| SELinux | **Permissive** | |
| Screen | 768×1024, 160 dpi, panel mounted with `hwrotation=270` | |
| Partitions | dynamic `super` (system, vendor, product), plus a vendor partition mounted at **`/great`** (configuration: `car.config`, whitelists, CAN box config) | |
| Bootloader | Locked, AVB green | |

Lesson: **the device decides**, not the listing or a forum dossier. `getprop` and
`/proc/cpuinfo` before believing anything.

## Root out of the box

The good news that makes everything else possible: **`adb shell` is already root**
(`uid=0`, SELinux context `u:r:su:s0`), even though `ro.debuggable=0`. `/system` and
`/vendor` are writable through overlayfs after `adb remount`.

```bash
adb shell id                # uid=0(root) ...
adb shell getenforce        # Permissive
adb remount                 # /system writable until next reboot
```

No Magisk, no unlocked bootloader, no custom ROM. That's also why there's no point looking
for one: the bootloader is locked, and there's no AOSP tree for UIS7862S. With factory root
and a writable overlay you get the same result, and you can undo it file by file.

> Security note: the flip side is that anyone who reaches ADB, or any app that obtains the
> `mcu_service` binder, has full control. The vendor's `mcu_service` doesn't check caller
> permissions (it only logs the pid/uid), and SELinux doesn't block it. Keep ADB off public
> networks.

## ADB over the network

USB ADB is the most reliable when you're at the car. For remote work the tested unit runs a
wireless-ADB app (`moe.haruue.wadb`) on a non-standard port, reachable only over a private
VPN (Tailscale). Port 5555 was closed on this ROM.

The unit is only online while the ignition is on (or for the standby time after it, see
[03](03-car-config.md#standby-time)).

## Tooling

- `adb` from Android platform-tools.
- [jadx](https://github.com/skylot/jadx) to read the vendor APKs. This is **the** technique:
  every answer below came from decompiling the vendor app that already does the thing.
  The useful ones: `QF_Framework.apk` (MCU service and client SDK), `QF_CarSettings.apk`
  (`KillApps`, standby), `QF_FMRadioExt.apk` (radio), `QF_Canbus.apk` (CAN box parsers),
  and `/system/framework/framework.jar` (vendor additions under `android.qf.*`).
- [apktool](https://apktool.org/) to patch smali in framework jars.

Pull them with:

```bash
adb shell pm path com.qf.framework
adb pull /system/priv-app/QF_Framework/QF_Framework.apk
adb pull /system/framework/framework.jar
```

## Vendor binder services

```
mcu_service        android.qf.mcu.IMcuManager          ← MCU: radio, keys, lights, CAN box
qfaudio            android.qf.os.IQFAudioService       ← volume
framework_service  android.qf.mcu.IQFFramework
config_service     android.qf.config.IConfigInfoManager
util_service       android.qf.util.IUtilEventManager
gestureServer      android.qf.util.IGlobalGestureBinder
emmc_service       android.qf.emmc.IEmmcManager
```

Useful properties set by the vendor:

| Property | Meaning |
|---|---|
| `sys.qf.top_pkg_name` | Package currently in the foreground |
| `persist.sys.qf.launcher` | Current HOME (but rewritten from `car.config` on boot, see [03](03-car-config.md)) |
| `persist.sys.qf.sleep_time` | Standby index (see [03](03-car-config.md#standby-time)) |
| `persist.sys.maps`, `persist.sys.dvr.app`, `persist.sys.obd.app`, `persist.sys.tpms.app` | Apps protected from `KillApps` (see [05](05-app-killers.md)) |
| `sys.qf.is.bt.on.when.accoff` | Bluetooth stays on with ignition off |
