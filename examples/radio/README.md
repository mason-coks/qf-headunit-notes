# FM radio through `mcu_service`

The tuner engine of a working replacement for the factory radio app, verified in the car
(seek, preset recall, reading presets, live frequency and signal). Protocol: [docs/07](../../docs/07-radio.md).

| File | |
|---|---|
| `McuRadioControl.kt` | Talks to the MCU by reflection: registers the package (binder transaction 1001), sends `0xA0` commands with `RPC_SendMcuMsgData`, listens with a `Proxy` implementing `android.qf.mcu.McuListener`, parses `B0` (signal), `B1` (frequency + presets) and `B6` (RDS name) |
| `RadioControl.kt` | The interface, a `RadioState` model, a simulated engine for the emulator, and a factory that picks the real one when `mcu_service` exists |

It's not a full app: there's no UI here. Drop both files into an Android module
(`targetSdk 29`) and call `RadioFactory.create(context)`.

Comments and some identifiers are in Spanish (`enviar` = send, `memoria` = preset,
`barrido` = scan, `emitir` = emit state).

Notes:

- The MCU only reports on change; the class persists the last real state in
  `SharedPreferences`.
- To open from the vendor radio button, the app has to replace `com.android.fmradio.ext` /
  `com.android.fmradio.FmMainActivity` (see docs/07, and mind `privapp-permissions` enforcement).
- Received MCU frames are logged raw with `Log.i` (tag `OtulaRadioMcu`). Sent commands use
  `Log.d`, which R8 strips in release builds; switch it to `Log.i` if you need to see them in
  the car.
