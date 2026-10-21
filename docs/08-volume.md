# 08 — Volume

## Symptoms

- `AudioManager.setStreamVolume` and `cmd media_session volume --set` change nothing.
  `dumpsys audio` shows **every stream stuck at 9**.
- `input keyevent KEYCODE_VOLUME_UP` is ignored; logcat says
  `QFKeyEvent: ignore key(KEYCODE_VOLUME_UP)`.
- `am broadcast -a com.qf.action.car_volume_control --ei extra_car_volume N` does nothing: no
  receiver is declared for it.

The amplifier volume belongs to the MCU. Android's mixer stays at a fixed level.

## What works

The vendor added `android.qf.os.VolumeManager` to `framework.jar`, backed by the `qfaudio`
binder (`android.qf.os.IQFAudioService`). The vendor volume widget uses it like this:

```java
VolumeManager.getInstance().getCurrentVolumeState().setVolumeVal(n);   // 0..32
int v = VolumeManager.getInstance().getCurrentVolumeState().getVolumeVal();
boolean muted = QFVolumeManager.getInstance().getVolumeStateMute();    // android.qf.volumemanager
```

The catch that cost a day: `VolumeManager` is a **per-process singleton that starts empty**.
The vendor bar calls `initVolumeManager(context)` on it at startup; until you do the same in
your own process, `getCurrentVolumeState()` returns `null`. `setVolumeVal` then writes
`sys.media.vol` and sends the level to the MCU with `McuManager.RPC_SetVolume`.

By reflection from a normal app (verified on the unit: 9 → 19):

```kotlin
val vm = Class.forName("android.qf.os.VolumeManager").getMethod("getInstance").invoke(null)!!
var state = vm.javaClass.getMethod("getCurrentVolumeState").invoke(vm)
if (state == null) {
    vm.javaClass.getMethod("initVolumeManager", Context::class.java).invoke(vm, applicationContext)
    state = vm.javaClass.getMethod("getCurrentVolumeState").invoke(vm)
}
state!!.javaClass.getMethod("setVolumeVal", Int::class.javaPrimitiveType).invoke(state, 19)
// mute: state.getVolumeStateMute() / state.setVolumeStateMute(Boolean)
```

Range 0–32. Default volumes per source live in `car.config` (`default_volume`,
`radio_volume`, `phone_volume`, `aux_volume`: 0–32; `navi_volume`: 0–15).

## Hands-free microphone

Phone calls over Bluetooth go through the **GOC** module (`/dev/goc_serial`, AT commands),
not through Android's audio effects. Enabling noise suppression in `audio_effects.xml` or
Z-Link's `persist.zj.apm.rnn` doesn't affect calls. The levers are the codec mic gain
(`tinymix`) or AT commands to the GOC module. Not solved on the tested unit.

And check that an `audio_effects.xml` change really loaded: the system says so at boot in a
line nobody reads (`XML effect configuration partially loaded, skipped 1 elements`). Verify
with `dumpsys media.audio_flinger` while something is recording.
