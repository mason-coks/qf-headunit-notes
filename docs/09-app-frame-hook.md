# 09 — Fitting apps into a custom launcher

Goal: a custom launcher with its own top strip (clock, icons, tabs) and bottom dock
(gauges, climate), and **a real app in the gap between them**, such as Waze or Z-Link
(CarPlay / Android Auto), working normally and not covered by anything.

It took five attempts. The short version: **apps open fullscreen as normal, and a 4-line hook
in `services.jar` tells the window manager that their frame is the gap.** The strip and dock
are `TYPE_APPLICATION_OVERLAY` windows of the launcher. The gap is a system property, so it
can be moved at runtime without reopening the app.

```
persist.sys.otula.appframe = "18 134 750 762"   ← home, radio, Z-Link (strip 128 + dock 256, 18 px side margins)
                           = "18 74 750 938"    ← navigation: Waze gets 864 px of height
```

(The format is `left top right bottom`, parsed with `Rect.unflattenFromString`.)

## Attempts that failed, so you can skip them

| # | Attempt | Why it failed |
|---|---|---|
| 1 | **Freeform windows** with `ActivityOptions.setLaunchBounds` | Android 10 forces the system bars on while a freeform window is visible (`DisplayPolicy.mForceShowSystemBars`) and ignores `policy_control`; the 160 + 154 px vendor bars covered the strip and dock. `setLaunchBounds` only applies when the activity creates a **new task**, so Z-Link (never killed by the ROM) reopened with its old task. Waze in freeform listed destinations but picking one didn't start the route. A tap within 30 dp of a freeform window's edge becomes a resize that gets stuck and swallows all touches |
| 2 | Fullscreen apps with strip and dock overlaid | Works with `policy_control` and the overscan trick from [04](04-fullscreen-and-bars.md), but the overlays cover the top and bottom of the app (Waze's buttons) |
| 3 | `wm overscan 18,134,18,262` to shrink the app area | Doesn't confine apps on this ROM (still `[0,0][768,1024]`) and brings the status bar back |
| 4 | **Hook in `services.jar`** | ✅ |

## The hook

The only change to Android code in the whole project, so it comes with a safety net.

1. Pull `services.jar` from the unit and disassemble it with apktool.
2. Add a new class, [`OtulaMarco`](../hooks/services-frame/OtulaMarco.smali), in
   `smali_classes2/com/android/server/wm/`. For windows of type 1 and 3
   (`TYPE_BASE_APPLICATION`, `TYPE_APPLICATION_STARTING`) on the default display, it returns
   the rect from `persist.sys.otula.appframe`. If the property is empty, or on **any**
   exception, it returns the rect it was given, so it behaves as if there were no hook.
3. In `WindowState.computeFrameLw`, right after label `:goto_6`, add
   [4 lines](../hooks/services-frame/WindowState.smali.diff) that pass the layout display frame
   (`v11`) and the layout containing frame (`v14`) through `OtulaMarco.marco()`.
4. Rebuild with apktool, and replace **only** `classes2.dex` inside a copy of the original jar,
   keeping each entry's original compression method (e.g. with Python's `zipfile`).
5. **Verify on the unit before installing:**
   `dex2oat --dex-file=<new jar> --compiler-filter=verify …` must report zero hard
   verification failures.
6. Install the safety net (below), install the jar with the property **empty**, reboot, and
   only then set the property. The tested unit did 3 clean boots before going further.

**The register numbers and the label are specific to this build.** On another ROM, check
that `:goto_6` and `v11`/`v14` mean the same thing in your `WindowState.smali` before applying
the diff. On Android 11+ `computeFrameLw` changed; you'd need to find the equivalent spot.

Without root this is impossible; attempt 2 is the best you can do.

### The safety net

[`otula-rescate.sh`](../hooks/services-frame/otula-rescate.sh), started from
[`otula_rescate.rc`](../hooks/services-frame/otula_rescate.rc) at `post-fs-data` (before
zygote starts), counts boots; `sys.boot_completed=1` resets the counter. After 3 boots in a
row that never completed, it **bind-mounts the original jar** over `services.jar` (it doesn't
write to `/system`), and the system comes up with the factory window manager. A false positive
(power cuts during boot) only disables the hook.

Keep the original jar on the unit at the path the script expects.

### The `launch_params` trap

After installing the hook, Waze **still** came up as a floating window with old bounds from
weeks before. While `enable_freeform_support` had been on, Android 10 saved each app's bounds
in `/data/system_ce/0/launch_params/`, and an app restored in freeform **skips the hook**.
Fix: freeform off (see [04](04-fullscreen-and-bars.md)) and empty that directory (back it up
first). If anyone turns freeform back on, it comes back.

## Polishing it

- **Per-screen layouts.** Since the gap is just a property, the launcher can give navigation a
  slimmer strip and dock (Waze went from 628 to 864 px tall, +38 %) and animate the gap when a
  climate panel slides up: send the new rect at each animation step.
- **Who sets the property.** The launcher isn't root and can't `setprop persist.sys.*`. On the
  tested unit a root shell script started by init watches a command directory the launcher
  writes into and runs the `setprop`. Measure that path's latency: with
  `inotifyd` failing on this ROM (`inotifyd - DIR:m` → `Invalid argument`), the script silently
  fell back to polling every 1 s and everything moved late. It polls every 0.1 s now.
- **The keyboard under the dock.** An app can't tell whether another app has the IME open, but
  an accessibility service can. A minimal service that only listens for "windows changed"
  (reading no content) lets the launcher hide the dock while the keyboard is visible.
- **Back to factory.** If the user switches HOME to the factory launcher, undo everything
  (clear the property, restore bars and `policy_control`), or the factory launcher shows up
  squeezed into the gap with no bars.

## Bonus hook: per-app density

Google Maps switches to tablet layout (search in a half-width side panel) because the screen
is 768 dp wide, above the 600 dp tablet threshold. `wm density` is global and would rescale
everything, and per-app density overrides arrived in Android 11.

[`OtulaDensidad.java`](../hooks/services-density/OtulaDensidad.java) hooks
`TaskRecord.resolveOverrideConfiguration` (wrapper in
[this diff](../hooks/services-density/TaskRecord.smali.diff)): for tasks whose package is in
`persist.sys.otula.dpi.apps` (comma-separated) it applies density `persist.sys.otula.dpi` and
recomputes width/height in dp and the screen size class. Maps then uses its phone layout. The
frame in pixels doesn't change. Without the properties, or on any error, it does nothing.
