# 04 — Fullscreen and system bars

The tested unit has a 160 px status bar at the top and a 154 px vendor navigation bar at the
bottom, on a 1024 px tall screen. Getting an app to use the whole screen took two sessions to
understand, because **it's two different problems**:

| Problem | Symptom | Fix |
|---|---|---|
| **A. The window frame is cropped** | Your app gets a 768×710 window and can't draw outside it, whatever flags it sets | Patch in `services.jar` (below) |
| **B. The bars are drawn on top** | Even with a 768×1024 frame, the bars cover the top and bottom | Immersive settings + the overscan trick |

> Hiding the bars doesn't enlarge the frame, and enlarging the frame doesn't hide the bars.
> You need both.

## A. The cropped frame

The QF/Spreadtrum window manager initialises the normal app frame to `Rect(0, 160, 768, 870)`.
On the tested unit this was patched in `classes2.dex` of `/system/framework/services.jar` to
`Rect(0, 0, 768, 1024)`, and the precompiled `.oat`/`.art`/`.vdex` files under
`/system/framework/oat/arm64/` were renamed so that `system_server` loads the patched jar.

Verified on real windows (`adb shell dumpsys window windows | grep mFrame`):

```
com.tailscale.ipn          mFrame=[0,0][768,1024]   ← full frame
launcher.horizon.city      mFrame=[0,0][768,1024]   ← full frame
com.syt.tmps               mFrame=[0,160][768,870]  ← still cropped
```

Apps that set `FORCE_NOT_FULLSCREEN` in their window flags still get the reduced area; that's
expected.

To revert: copy the original jar back and rename the `.oat` files back, then reboot.

Side effect: the factory launcher (`horizon.city`) uses a root `FrameLayout` with no inset
handling, so its app drawer started at y=0 under the status bar. Fixed with a static
**RRO overlay** in `/system/product/overlay/` that sets `paddingTop=160px` and
`paddingBottom=154px` on its `launcher.xml`. It's a new file and doesn't touch any vendor file;
delete it to revert.

> If you are writing a custom launcher, [09](09-app-frame-hook.md) replaces this whole
> approach with a hook that can set any frame at runtime.

## B. Hiding the bars

### Immersive mode for your apps

```bash
adb shell settings put global policy_control "immersive.full=com.example.launcher,com.waze,com.zjinnova.zlink"
adb shell settings put secure nav_bar_force_visible 0
adb shell settings put global force_immersive_on_app <package>     # vendor hook
```

Use a comma-separated list rather than `*`: with `immersive.full=*`, if someone opens the
vendor launcher or Z-Link from outside your launcher, there's no bar left to get back with.

`policy_control` is **ignored while any freeform window is visible** (Android 10 forces the
bars on: `DisplayPolicy.mForceShowSystemBars`). Disable freeform:

```bash
adb shell settings put global enable_freeform_support 0
adb shell settings put global force_resizable_activities 0
# reboot
```

Tasks that were already freeform survive the reboot with their bounds. Move them back:
`am stack list`, then `am stack move-task <task> <fullscreen-stack> true`. Also see the
`launch_params` trap in [09](09-app-frame-hook.md#the-launch_params-trap).

### Removing the vendor bars for real

```bash
# bottom bar (154 px) — persists
adb shell settings put system show_navigationbar 0
adb shell setprop persist.sys.qf.show.navibar false

# top bar (160 px) — pushes it off the screen; persists
adb shell wm overscan 0,-160,0,0
```

Revert: `wm overscan reset`, `show_navigationbar 1`, `persist.sys.qf.show.navibar true`.

Side effect of the negative overscan: windows with `FLAG_LAYOUT_NO_LIMITS` (overlays) are
placed relative to the "unrestricted" area, whose origin moves to y = −160. They jump 160 px
up. Activities and freeform windows don't move. **Fix:** anchor overlays to the bottom edge
(`Gravity.BOTTOM`, `y` counted from the bottom). The bottom edge is 1024 with or without
overscan.

### Four ways to hide the status bar that don't work

| Attempt | Result |
|---|---|
| `pm disable-user com.android.systemui` / `pm disable` + `kill` | It restarts by itself (persistent app) and the bar is still there. Also risky: you can lose system UI |
| `setprop sys.status_bar_height 0` / `persist.sys.status_bar_height 0`, even restarting SystemUI | `mStable` still reserves 160 px |
| `sys.qf.statusbar.state` set to 0 / 1 / 3 | No effect |
| `am stack resize <fullscreen stack>` | Ignored: a fullscreen stack doesn't accept bounds |

And one that looks like it should shrink the app area: `wm overscan 18,134,18,262`. **On
this ROM it doesn't confine apps** (measured: Waze stayed at `[0,0][768,1024]`) and the status
bar came back. Overscan is only good for pushing the top bar off-screen.

## Bottom bar height: 48 px vs 154 px

If the bottom bar shows up compact (48 px), the navigation mode must be **three-button**, not
gestural (with the `gestural` overlay the bar stays compact). The vendor's configurable bar
height is only read when `QFApi.getProjectType()` starts with `"navi"`.
