# Replicar la solución tras actualización del kernel

> [English](../KERNEL-UPDATE.md) | **Español**

Documento **teórico**: estrategias para que el audio siga funcionando cada vez que Ubuntu instala un kernel nuevo (`linux-image-*`, `linux-headers-*`).

---

## Por qué hay que repetir el proceso

Los módulos parcheados (`snd-soc-tas2783-sdw.ko`, `snd-soc-sdw-utils.ko`) se compilan contra un **vermagic** concreto. Tras `apt upgrade`:

1. El kernel en ejecución cambia (o quedará pendiente hasta reiniciar).
2. Los `.ko` instalados en `/lib/modules/VIEJA_VERSION/` **no** cargan en la nueva versión.
3. Vuelves al stack vanilla → pueden reaparecer -22, -110 o mono.

El **firmware** en `/usr/lib/firmware/` **no** depende del kernel: solo se instala una vez (salvo reinstalación limpia).

---

## Flujo mínimo repetible (manual)

```
apt upgrade → nuevo kernel KVER
     ↓
reboot (opcional: arrancar el kernel nuevo)
     ↓
prepare-kernel-tree.sh      # fuentes alineadas con KVER
     ↓
build-production-modules.sh # parches 0004+0006+0007+0009
     ↓
reboot
     ↓
verificar: speaker-test / dmesg | grep -i tas2783
```

Tiempo estimado: 5–15 min (compilación en PX13).

---

## Estrategias de automatización

### A — Script post-actualización (recomendado para un solo equipo)

**Idea:** hook que detecta kernels nuevos sin módulos parcheados.

| Componente | Función |
|------------|---------|
| `scripts/build-production-modules.sh` | Compila e instala para `uname -r` |
| Script wrapper `post-kernel-update.sh` | Comprueba si existen `.ko` parcheados; si no, compila |
| Trigger | `apt` hook (`/etc/apt/apt.conf.d/`) o cron `@reboot` |

**Ventajas:** simple, sin DKMS, control total.  
**Inconvenientes:** requiere `linux-headers-$(uname -r)` y `build-essential` instalados.

```
/etc/apt/apt.conf.d/99-snd-repair
  → DPkg::Post-Invoke ejecuta post-kernel-update.sh si cambió linux-image
```

### B — DKMS

**Idea:** empaquetar el código parcheado como módulo DKMS; al instalar headers nuevos, DKMS recompila solo.

| Paso | Acción |
|------|--------|
| 1 | Crear `/usr/src/snd-repair-tas2783-1.0/` con fuentes parcheadas + `dkms.conf` |
| 2 | `dkms add` / `dkms build` / `dkms install` |
| 3 | Cada `apt install linux-headers-*` dispara rebuild automático |

**Ventajas:** estándar en Ubuntu, integración con `dkms autoinstall`.  
**Inconvenientes:** mantener dos módulos (tas2783 + sdw_utils), empaquetado inicial más laborioso; parche 0009 toca dos árboles.

### C — Paquete .deb local (`debian/`)

**Idea:** `debian/rules` que aplica parches, compila contra headers del paquete `linux-headers-$KVER` y empaqueta los `.ko.zst`.

```
snd-repair-dkms_1.0_amd64.deb
  → depende de: linux-headers-generic | linux-headers-$(uname -r)
  → postinst: instala en /lib/modules/$KVER/...
```

**Ventajas:** reproducible, versionable, instalable con `dpkg -i`.  
**Inconvenientes:** hay que generar un .deb **por** versión de kernel o usar DKMS dentro del paquete.

### D — Esperar merge upstream

**Idea:** cuando las series A/C/B de [`upstream/`](../upstream/README.md) entren en el kernel estable, **no** harán falta módulos locales.

| Serie | Estado deseado |
|-------|------------------|
| A (capture) | En kernel mainline |
| C (channel map) | En kernel mainline |
| B (firmware retry) | En kernel mainline |

**Ventajas:** cero mantenimiento tras la versión de kernel que los incluya.  
**Inconvenientes:** plazo incierto; mientras tanto, B o C local.

### E — Arranque dual: kernel “congelado”

**Idea:** mantener en GRUB una entrada con el último kernel **validado** + módulos ya compilados.

**Ventajas:** refugio si un kernel nuevo rompe algo.  
**Inconvenientes:** no es solución definitiva; seguridad y soporte de kernels viejos limitado.

---

## Matriz de decisión

| Criterio | Manual | apt hook | DKMS | .deb propio | Upstream |
|----------|--------|----------|------|-------------|----------|
| Esfuerzo inicial | Bajo | Medio | Alto | Alto | Ninguno (esperar) |
| Mantenimiento | Alto | Medio | Bajo | Medio | Nulo |
| Tras cada kernel | Manual | Semi-auto | Auto | Semi-auto | Nada |
| Portabilidad | Solo tu PC | Solo tu PC | Buena | Buena | Universal |

**Recomendación práctica para PX13:**

1. **Corto plazo:** `build-production-modules.sh` + recordatorio post-`apt upgrade` (o hook apt).
2. **Medio plazo:** empaquetar en DKMS si actualizas kernel a menudo.
3. **Largo plazo:** contribuir upstream (`upstream/`) y retirar parches locales cuando el kernel los incorpore.

---

## Checklist tras cada actualización de kernel

- [ ] `uname -r` coincide con el kernel que quieres usar
- [ ] `linux-headers-$(uname -r)` instalado
- [ ] `prepare-kernel-tree.sh` ejecutado sin error
- [ ] `build-production-modules.sh` instaló ambos `.ko.zst`
- [ ] `modinfo snd_soc_tas2783_sdw | grep vermagic` coincide con `uname -r`
- [ ] `dmesg | grep -i tas2783` sin `error playback without fw` ni `-22`
- [ ] `speaker-test` L y R por separado

---

## Qué **no** hay que repetir

| Elemento | ¿Repetir? |
|----------|-----------|
| Firmware `/usr/lib/firmware/` | No |
| Configuración PipeWire/Pulse | No |
| Parches en el repo (`patches/`) | No (solo re-aplicar al árbol nuevo) |
| Validación 20–30 boots (Serie B) | Solo si cambia hardware o driver base |
