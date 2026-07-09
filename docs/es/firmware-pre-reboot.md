# Estado técnico pre-reinicio

> [English](../firmware-pre-reboot.md) | **Español**

Instantánea del sistema antes de `sudo reboot` durante la configuración de la matriz de symlinks de firmware.

---

## Estado del sistema (pre-reinicio)

### Hechos confirmados

1. **Hardware operativo:** `ls -la /sys/bus/soundwire/devices/` muestra los **tres** dispositivos: codec Realtek (`rt721`) y **dos** amplificadores TI en `0x8` (izquierdo) y `0xB` (derecho).
2. **Causa en el firmware del chip (no en la topología SOF):** `dmesg` registra `-22` (EINVAL) con `error playback without fw download` — el driver rechaza la reproducción sin los bytes de calibración en el silicio del amplificador.
3. **Fallo en cascada:** si la carga de firmware falla en el primer amplificador (`0x8`), ALSA/ASoC interrumpe la inicialización del bloque de altavoces; el segundo (`0xB`) puede no registrarse en el mixer.

---

## Matriz de symlinks en `/usr/lib/firmware/`

El driver no registra el nombre exacto del fichero de firmware (depende del parseo ACPI). Se creó una **matriz de symlinks de compatibilidad**:

| Ruta / symlink | Variante cubierta |
|----------------|-------------------|
| `ti/1714-1-8.bin` / `ti/1714-1-b.bin` | Estructura estándar TI (minúsculas) |
| `1714_1_8.bin` / `1714_1_B.bin` | Formato con guiones bajos (común en parches ASUS) |
| `ti/tas2783-8.bin` / `ti/tas2783-b.bin` | Nomenclatura por ID de dispositivo |
| `tas2783-1714-1-0x8.bin` / `tas2783-1714-1-0xb.bin` | Dirección de bus en hexadecimal |

---

## Pasos tras el reinicio

El kernel debe volver a cargar los drivers para escanear la nueva matriz. Tras el arranque, ejecutar:

```bash
sudo dmesg | grep -i tas2783
```

### Dos escenarios esperados

* **Escenario A (éxito):** desaparecen las líneas `error playback without fw download`; inicialización del codec sin error; el canal derecho puede quedar operativo.
* **Escenario B (persistencia):** el error continúa — el kernel espera otro nombre de fichero; capturar la ruta exacta con `strace` o `perf` sobre la inicialización del bus.

### Reinicio

Con la matriz de symlinks desplegada, proceder al reinicio:

```bash
sudo reboot
```

Tras el arranque, repetir la comprobación con `dmesg` y registrar el resultado para la siguiente iteración del diagnóstico.
