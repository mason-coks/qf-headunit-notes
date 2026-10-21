package com.example.qfradio

import android.content.Context
import android.util.Log
import java.lang.reflect.Proxy

/**
 * Motor REAL de la radio del K706.
 *
 * ⚠️ Lo importante, porque el proyecto lo tuvo mal durante meses: **la radio de este coche NO se
 * controla con `RadioManager` / BroadcastRadio HAL de Android**. La app de fábrica
 * (`com.android.fmradio.ext`, descompilada el 31 jul 2026) habla con el **MCU** de la unidad —el
 * microcontrolador que está cableado a la antena— a través del servicio de sistema `mcu_service`.
 * El `broadcastradio-hal2` que corre en la pantalla es la FM del SoC Spreadtrum, que no está
 * conectada a la antena del coche. Ver docs/07-radio.md.
 *
 * Se usa reflexión porque `android.qf.mcu.McuManager` es una clase que el vendor añadió a su
 * `framework.jar`: existe en el dispositivo pero no en el SDK contra el que compilamos.
 *
 *   McuManager mcu = (McuManager) ctx.getSystemService("mcu_service");
 *   mcu.RPC_SendMcuMsgData(byte cid, byte[] data, int len);
 *   mcu.RPC_RequestMcuInfoChangedListener(McuListener l);   // l.onMcuInfoChanged(byte[])
 *
 * `McuListener` es una interfaz Java normal (no AIDL), así que se implementa con un Proxy dinámico.
 */
class McuRadioControl(ctx: Context) : RadioControl {

    private val tag = "OtulaRadioMcu"
    private val prefs = ctx.getSharedPreferences("radio", Context.MODE_PRIVATE)
    private val mcu: Any = ctx.getSystemService("mcu_service")
        ?: throw IllegalStateException("mcu_service no disponible en este dispositivo")

    private val sendMethod = mcu.javaClass.getMethod(
        "RPC_SendMcuMsgData",
        java.lang.Byte.TYPE, ByteArray::class.java, Integer.TYPE
    )

    private var cb: ((RadioState) -> Unit)? = null

    /**
     * Arranca con lo último que dijo el MCU de verdad, no con valores inventados: el MCU solo
     * informa cuando hay actividad, así que si no recordáramos nada la pantalla enseñaría
     * memorias falsas hasta que el usuario tocase algo.
     */
    override var state = RadioState(
        on = true,
        signal = 0,
        freqKhz = prefs.getInt("freq", 0).takeIf { it > 0 } ?: Band.FM.minKhz,
        presets = prefs.getString("presets", null)
            ?.split(",")?.mapNotNull { it.toIntOrNull() }
            ?: emptyList()
    )
        private set

    init {
        registrarPermisoAnteElMcu(ctx.packageName)
        escucharAlMcu()
        Log.i(tag, "Motor MCU listo")
    }

    // ---------------------------------------------------------------- envío

    /** Toda orden al sintonizador es [CMD_TUNER, subcomando, p1, p2]. */
    private fun enviar(sub: Int, p1: Int = 0, p2: Int = 0) {
        try {
            val payload = byteArrayOf(sub.toByte(), p1.toByte(), p2.toByte())
            sendMethod.invoke(mcu, CMD_TUNER.toByte(), payload, payload.size)
            Log.d(tag, "→ MCU A0 %02X %02X %02X".format(sub, p1, p2))
        } catch (e: Exception) {
            Log.e(tag, "fallo enviando la orden $sub al MCU", e)
        }
    }

    override fun powerOn() { state = state.copy(on = true); emitir() }
    override fun powerOff() { state = state.copy(on = false); emitir() }

    override fun tuneTo(khz: Int) {
        val b = state.band
        val f = khz.coerceIn(b.minKhz, b.maxKhz)
        // El MCU espera la frecuencia en 2 bytes big-endian, en las unidades del dial:
        // FM en decenas de kHz (94.60 MHz → 9460), AM en kHz.
        val valorDial = if (b == Band.FM) f / 10 else f
        enviar(SUB_TUNE_FRECUENCIA, (valorDial shr 8) and 0xFF, valorDial and 0xFF)
        // Optimista: el MCU confirmará con 0xB0 y corregirá si hace falta.
        state = state.copy(freqKhz = f, rds = "")
        emitir()
    }

    override fun seekUp() = enviar(SUB_SEEK_UP)
    override fun seekDown() = enviar(SUB_SEEK_DOWN)

    /** Un paso de dial: la "décima" de FM. */
    fun pasoArriba() = enviar(SUB_FINE_UP)
    fun pasoAbajo() = enviar(SUB_FINE_DOWN)

    override fun setBand(band: Band) {
        enviar(SUB_CAMBIAR_BANDA, if (band == Band.FM) 0 else 1)
        state = state.copy(band = band)
        emitir()
    }

    override fun savePreset(slot: Int) = enviar(SUB_GUARDAR_MEMORIA, slot + 1)
    override fun recallPreset(slot: Int) = enviar(SUB_IR_A_MEMORIA, slot + 1)

    /** Barrido automático que además guarda las emisoras encontradas. */
    fun autoBuscarYGuardar() = enviar(SUB_AUTO_STORE)
    fun empezarBarrido() = enviar(SUB_BARRIDO_INICIO)
    fun pararBarrido() = enviar(SUB_BARRIDO_PARAR)

    /** Filtrar por categoría del RDS (noticias, pop, deportes…). */
    fun filtrarPorCategoria(pty: Int) = enviar(SUB_RDS_PTY, pty)

    fun conmutarTrafico() = enviar(SUB_RDS_TA)
    fun conmutarFrecuenciasAlternativas() = enviar(SUB_RDS_AF)

    override fun setMute(mute: Boolean) {
        state = state.copy(muted = mute)
        emitir()
    }

    // -------------------------------------------------------------- recepción

    /**
     * El MCU avisa de todo por `onMcuInfoChanged(byte[])`, con el código en el primer byte.
     * Nos quedamos con lo que le interesa a la interfaz: frecuencia/banda/señal, memorias y RDS.
     */
    private fun escucharAlMcu() {
        try {
            val listenerClass = Class.forName("android.qf.mcu.McuListener")
            val listener = Proxy.newProxyInstance(
                listenerClass.classLoader, arrayOf(listenerClass)
            ) { proxy, method, args ->
                // Ojo: `McuManager.wrapListener` mete el oyente en un HashMap, así que llama a
                // hashCode()/equals(). Un proxy que devuelva null en hashCode revienta al
                // desempaquetar el int — es exactamente lo que pasó en el primer intento.
                when (method.name) {
                    "onMcuInfoChanged" -> {
                        (args?.getOrNull(0) as? ByteArray)?.let { procesar(it) }
                        null
                    }
                    "hashCode" -> System.identityHashCode(proxy)
                    "equals" -> proxy === args?.getOrNull(0)
                    "toString" -> "OtulaMcuListener"
                    else -> null
                }
            }
            mcu.javaClass
                .getMethod("RPC_RequestMcuInfoChangedListener", listenerClass)
                .invoke(mcu, listener)
            Log.i(tag, "Escuchando al MCU")
        } catch (e: Exception) {
            Log.e(tag, "no se pudo escuchar al MCU; la interfaz irá 'a ciegas'", e)
        }
    }

    private fun procesar(datos: ByteArray) {
        if (datos.isEmpty()) return
        // Volcado en crudo: imprescindible para ajustar el formato real (unidades de la
        // frecuencia, posición de los bytes) sin adivinar.
        Log.i(tag, "← MCU " + datos.joinToString(" ") { "%02X".format(it) })
        when (datos[0].toInt() and 0xFF) {
            /*
             * Formato REAL, capturado del coche el 31 jul 2026 (no adivinado):
             *
             *   B1 00 00 | 25 0D | 22 60 22 B0 23 32 24 AE 24 F4 25 C6
             *   └cmd     └banda  └freq  └───────── las 6 memorias ──────────┘
             *
             * La frecuencia va en DECENAS de kHz: 0x250D = 9485 → 94.85 MHz. Se validó contra la
             * app de fábrica: las memorias de arriba son exactamente 88.00 / 88.80 / 90.10 /
             * 93.90 / 94.60 / 96.70, las que tenía guardadas el coche.
             */
            RESP_LISTA_MEMORIAS -> {
                var cambiado = false
                if (datos.size >= 5) {
                    val khz = dialAKhz(((datos[3].toInt() and 0xFF) shl 8) or (datos[4].toInt() and 0xFF))
                    if (khz in state.band.minKhz..state.band.maxKhz && khz != state.freqKhz) {
                        state = state.copy(freqKhz = khz); cambiado = true
                    }
                }
                if (datos.size >= 17) {
                    val memorias = (0 until 6).map {
                        val i = 5 + it * 2
                        dialAKhz(((datos[i].toInt() and 0xFF) shl 8) or (datos[i + 1].toInt() and 0xFF))
                    }
                    if (memorias != state.presets) { state = state.copy(presets = memorias); cambiado = true }
                }
                if (cambiado) emitir()
            }
            /** `B0 58` → un byte con la calidad de señal (0x58 = 88 sobre 100). */
            RESP_ESTADO_SINTONIZADOR -> {
                if (datos.size >= 2) {
                    val calidad = datos[1].toInt() and 0xFF
                    val barras = (calidad * 4 / 100).coerceIn(0, 4)
                    if (barras != state.signal) { state = state.copy(signal = barras); emitir() }
                }
            }
            RESP_NOMBRE_EMISORA -> {
                // [0xB6, texto PS en ASCII]
                val ps = String(datos, 1, datos.size - 1, Charsets.US_ASCII)
                    .filter { it.code in 32..126 }.trim()
                if (ps.isNotEmpty() && ps != state.rds) { state = state.copy(rds = ps); emitir() }
            }
        }
    }

    /**
     * El MCU exige que la app se dé de alta por su nombre de paquete antes de aceptarle órdenes
     * (transacción 1001 del binder, tal cual hace el SDK del vendor en `QFCoreManager`).
     */
    private fun registrarPermisoAnteElMcu(paquete: String) {
        try {
            val sm = Class.forName("android.os.ServiceManager")
            val binder = sm.getMethod("getService", String::class.java)
                .invoke(null, "mcu_service") as android.os.IBinder
            val datos = android.os.Parcel.obtain()
            val respuesta = android.os.Parcel.obtain()
            try {
                datos.writeInterfaceToken(binder.interfaceDescriptor ?: "android.qf.mcu.IMcuManager")
                datos.writeString(paquete)
                binder.transact(TRANSACCION_PEDIR_PERMISO, datos, respuesta, 0)
                Log.i(tag, "Permiso pedido al MCU para $paquete")
            } finally {
                respuesta.recycle(); datos.recycle()
            }
        } catch (e: Exception) {
            Log.w(tag, "no se pudo pedir permiso al MCU (puede que no haga falta)", e)
        }
    }

    /** El MCU habla en decenas de kHz en FM (9485 = 94.85 MHz) y en kHz en AM. */
    private fun dialAKhz(dial: Int): Int = if (state.band == Band.FM) dial * 10 else dial

    private fun emitir() {
        prefs.edit()
            .putInt("freq", state.freqKhz)
            .putString("presets", state.presets.joinToString(","))
            .apply()
        cb?.invoke(state)
    }
    override fun onStateChanged(cb: (RadioState) -> Unit) { this.cb = cb }

    companion object {
        // Familia de comandos del sintonizador (ARM → MCU)
        private const val CMD_TUNER = 0xA0

        private const val SUB_TUNE_FRECUENCIA = 0x00
        private const val SUB_SEEK_UP = 0x01
        private const val SUB_SEEK_DOWN = 0x02
        private const val SUB_FINE_UP = 0x03
        private const val SUB_FINE_DOWN = 0x04
        private const val SUB_BARRIDO_INICIO = 0x05
        private const val SUB_CAMBIAR_BANDA = 0x06
        private const val SUB_AUTO_STORE = 0x08
        private const val SUB_GUARDAR_MEMORIA = 0x0B
        private const val SUB_BARRIDO_PARAR = 0x0C
        private const val SUB_IR_A_MEMORIA = 0x0D
        private const val SUB_RDS_AF = 0x11
        private const val SUB_RDS_TA = 0x12
        private const val SUB_RDS_PTY = 0x15

        // Respuestas del MCU
        private const val RESP_ESTADO_SINTONIZADOR = 0xB0
        private const val RESP_LISTA_MEMORIAS = 0xB1
        private const val RESP_NOMBRE_EMISORA = 0xB6

        private const val TRANSACCION_PEDIR_PERMISO = 1001

        /** ¿Tiene este dispositivo el servicio del MCU? */
        fun disponible(ctx: Context): Boolean = try {
            ctx.getSystemService("mcu_service") != null
        } catch (e: Exception) { false }
    }
}
