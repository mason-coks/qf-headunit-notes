# Notas de la pantalla Android china Qianfeng (QF) — K706 / UIS7862S

Resumen en español. La documentación completa está en inglés, en [`docs/`](docs/).

Son notas de campo de varios meses desmontando una pantalla Android china de coche (K706,
ROM Qianfeng, Unisoc UIS7862S, Android 10 aunque la venden como Android 14), **medidas en una
unidad real montada en un coche**. Lo que no está probado va marcado como tal, y los caminos
que no funcionaron están tan documentados como las soluciones.

> [!WARNING]
> Estas unidades traen **ADB con root** y `/system` escribible. Es fácil dejarlas sin launcher,
> sin interfaz o sin arrancar. Lee [`docs/00-safety.md`](docs/00-safety.md) antes de tocar
> nada. Sin garantía: bajo tu responsabilidad.

## Lo más útil, en una línea cada cosa

- **ADB es root de fábrica** y `/system` se puede escribir con `adb remount`. No hace falta
  otra ROM (ni existe: bootloader bloqueado y sin AOSP para UIS7862S).
- **Bluetooth, radio, volumen, HOME y la muerte de apps no son Android**, sino una capa del
  fabricante: el daemon GOC, el MCU y `car.config`. La API de Android "funciona" y no hace
  nada. → [02](docs/02-who-controls-what.md)
- **El launcher por defecto y el tiempo de standby se guardan en `/great/protect_dir/car.config`**,
  no en las properties: `setprop` se pierde al reiniciar. `sleep_time` es un índice
  (1 = 2 h, 2 = 1 día…). → [03](docs/03-car-config.md)
- **La pantalla completa son dos problemas**: el marco recortado (parche de `services.jar`) y
  las barras pintadas encima (`policy_control` + `wm overscan 0,-160,0,0` +
  `show_navigationbar 0`). → [04](docs/04-fullscreen-and-bars.md)
- **Hay dos procesos que matan apps**: `KillApps` (lista `bg_white_list.config`) y
  `QFSleepWakeup` antes de dormir (lista `/great/sleep/sleep_whitelist`, que hay que crear).
  Y por qué una VPN que arranca tarde le corta el Z-Link al móvil. → [05](docs/05-app-killers.md)
- **El protocolo del MCU** (tramas UART, comandos, caja CAN Hiworld). → [06](docs/06-mcu-protocol.md)
- **La radio FM cuelga del MCU**, no de `RadioManager`: comandos `0xA0`, respuestas
  `0xB0`–`0xB8`, y código Kotlin que funciona. → [07](docs/07-radio.md)
- **El volumen lo lleva el MCU**: todos los streams de Android están clavados en 9. Se cambia
  con `android.qf.os.VolumeManager` tras `initVolumeManager(context)`. → [08](docs/08-volume.md)
- **Meter Waze o el Z-Link en el hueco de un launcher propio**: un gancho de 4 líneas en
  `services.jar` con red de seguridad contra bucles de arranque. → [09](docs/09-app-frame-hook.md)
- **Otras trampas**: ninguna alarma despierta la unidad, el A-GPS apunta a un servidor chino
  (y hay dos copias de la configuración), el `.bak` en `/system/etc/init/`… → [10](docs/10-other-traps.md)

## Carpetas

- [`scripts/`](scripts/): recogida de información (solo lectura) y scripts para aplicar y
  deshacer los ajustes (por defecto solo enseñan lo que harían).
- [`hooks/`](hooks/): fuentes smali/Java y diffs de los ganchos de `services.jar`. **No se
  distribuye ningún binario del fabricante.**
- [`examples/radio/`](examples/radio/): la clase Kotlin que maneja el sintonizador por `mcu_service`.

Licencia: documentación CC BY 4.0, código MIT ([LICENSE](LICENSE)).
