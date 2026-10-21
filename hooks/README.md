# `services.jar` hooks

Sources only. **No `services.jar` is distributed here**: you have to patch the one from your
own unit, because offsets, labels and register numbers depend on the build. Background and the
full procedure: [docs/09](../docs/09-app-frame-hook.md). Comments in the files are in Spanish.

Tested on: `ROCO/K706/K706:10/QP1A.190711.020`, build `QF001.20250408.135749`, Android 10.

## `services-frame/` — put app windows in a rect

| File | What |
|---|---|
| `OtulaMarco.smali` | New class `com.android.server.wm.OtulaMarco`. `marco(WindowState, Rect)` returns the rect in `persist.sys.otula.appframe` for window types 1 and 3 on the default display, or the input rect otherwise / on any error |
| `WindowState.smali.diff` | The 4 lines added after `:goto_6` in `WindowState.computeFrameLw`. **Check that `:goto_6`, `v11` (`layoutDisplayFrame`) and `v14` (`layoutContainingFrame`) match your build** |
| `otula-rescate.sh` | Boot counter run at `post-fs-data`; after 3 incomplete boots, bind-mounts the original jar. Edit `B=` to where you keep the original |
| `otula_rescate.rc` | init file that runs it and resets the counter on `sys.boot_completed=1` |

Usage after install:

```bash
adb shell setprop persist.sys.otula.appframe "18 134 750 762"   # left top right bottom
adb shell setprop persist.sys.otula.appframe ""                  # off (factory behaviour)
```

## `services-density/` — per-app density

| File | What |
|---|---|
| `OtulaDensidad.java` / `.smali` | `ajusta(task, out, parent)`: for packages in `persist.sys.otula.dpi.apps`, applies `persist.sys.otula.dpi` and recomputes dp sizes and screen size class |
| `TaskRecord.smali.diff` | Normal `diff` (no context). Renames the original `resolveOverrideConfiguration(Configuration)` body to a private `resolveOverrideConfigurationOtula` and inserts a wrapper that calls it and then `OtulaDensidad.ajusta` |

```bash
adb shell setprop persist.sys.otula.dpi 120
adb shell setprop persist.sys.otula.dpi.apps com.google.android.apps.maps
```

## Build outline

```bash
java -jar apktool.jar d -f -o svc services.jar          # YOUR unit's services.jar
cp OtulaMarco.smali svc/smali_classes2/com/android/server/wm/
# apply WindowState.smali.diff by hand after checking labels and registers
java -jar apktool.jar b svc -o rebuilt.jar
# copy classes2.dex from rebuilt.jar into a COPY of the original services.jar,
# keeping each zip entry's compression method
# on the unit, before installing:
#   dex2oat --dex-file=/data/local/tmp/services-new.jar --compiler-filter=verify \
#           --oat-file=/data/local/tmp/x.oat   → no "hard verification" failures
```

Install order that worked: safety net first → new jar with the property empty → reboot ×3 →
set the property. Disable or rename the precompiled `services.{art,odex,vdex}` in
`/system/framework/oat/arm64/` so `system_server` loads the patched jar.
