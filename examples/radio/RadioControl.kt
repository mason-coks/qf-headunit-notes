package com.example.qfradio

import android.content.Context

/**
 * Motor de radio desconectable: [McuRadioControl] en la pantalla (MCU) y [StubRadioControl]
 * (simulado) en el emulador, para poder ver la interfaz sin coche.
 */
interface RadioControl {
    val state: RadioState
    fun powerOn()
    fun powerOff()
    fun tuneTo(khz: Int)
    fun seekUp()
    fun seekDown()
    fun setBand(band: Band)
    fun savePreset(slot: Int)
    fun recallPreset(slot: Int)
    fun setMute(mute: Boolean)
    fun onStateChanged(cb: (RadioState) -> Unit)
}

enum class Band(val label: String, val minKhz: Int, val maxKhz: Int, val stepKhz: Int) {
    FM("FM", 87_500, 108_000, 100),
    AM("AM", 522, 1_710, 9)
}

data class RadioState(
    val on: Boolean = true,
    val band: Band = Band.FM,
    val freqKhz: Int = 93_900,
    val rds: String = "",
    val signal: Int = 0,            // 0..4
    val muted: Boolean = false,
    val presets: List<Int> = listOf(93_900, 89_000, 98_800, 101_500, 104_300, 106_000)
) {
    fun freqLabel(): String =
        if (band == Band.FM) String.format("%.1f", freqKhz / 1000.0) else "$freqKhz"
    fun unitLabel(): String = if (band == Band.FM) "MHz" else "kHz"
}

/** Implementación simulada para desarrollo sin coche. */
class StubRadioControl : RadioControl {
    override var state = RadioState(rds = "STUB FM", signal = 3)
        private set
    private var cb: ((RadioState) -> Unit)? = null
    private fun emit() { cb?.invoke(state) }

    override fun powerOn()  { state = state.copy(on = true); emit() }
    override fun powerOff() { state = state.copy(on = false); emit() }
    override fun tuneTo(khz: Int) {
        val b = state.band
        state = state.copy(freqKhz = khz.coerceIn(b.minKhz, b.maxKhz), rds = "—"); emit()
    }
    override fun seekUp()   { tuneTo(state.freqKhz + state.band.stepKhz * 5) }
    override fun seekDown() { tuneTo(state.freqKhz - state.band.stepKhz * 5) }
    override fun setBand(band: Band) {
        state = state.copy(band = band, freqKhz = band.minKhz); emit()
    }
    override fun savePreset(slot: Int) {
        val p = state.presets.toMutableList()
        if (slot in p.indices) p[slot] = state.freqKhz
        state = state.copy(presets = p); emit()
    }
    override fun recallPreset(slot: Int) {
        state.presets.getOrNull(slot)?.let { tuneTo(it) }
    }
    override fun setMute(mute: Boolean) { state = state.copy(muted = mute); emit() }
    override fun onStateChanged(cb: (RadioState) -> Unit) { this.cb = cb }
}

object RadioFactory {
    /**
     * En la pantalla del coche usa el motor real (MCU); en cualquier otro sitio —emulador, PC—
     * cae al simulado para poder ver la interfaz sin coche.
     *
     * Nada de `RadioManager`/HAL2: NO controla la radio de este coche. El motor bueno es
     * [McuRadioControl]; protocolo en docs/07-radio.md.
     */
    fun create(ctx: Context): RadioControl =
        try {
            if (McuRadioControl.disponible(ctx)) McuRadioControl(ctx) else StubRadioControl()
        } catch (e: Throwable) {
            android.util.Log.w("OtulaRadio", "sin MCU, uso el motor simulado", e)
            StubRadioControl()
        }
}
