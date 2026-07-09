# Serie B — Validación pendiente antes de enviar como patch formal

## Matriz mínima

- [ ] **20–30 reinicios** consecutivos; registrar `dmesg | grep -i 'FW download'`
- [ ] **Suspend/resume** ×10 (`systemctl suspend` o tapa)
- [ ] **Rates:** 44100, 48000, 96000 Hz (`speaker-test -r`)
- [ ] **Buffer sizes:** mínimo y máximo ALSA (`speaker-test -b`)

## Datos preliminares (7 boots, pre-RFC)

| Métrica | Sin 0006+0007 | Con 0006+0007 |
|---------|---------------|---------------|
| Boots totales | 7 | 7 (Boot 7 representativo) |
| UID `0x8` FW fail | 0/7 | 0/7 |
| UID `0xb` FW fail | ~3–4/7 (intermitente) | 0/1 en Boot 7 |
| Estéreo L/R | Solo-L (Problema C) | OK tras Serie C |

**Conclusión provisional:** mejora clara en Boot 7; **insuficiente** para parche formal. Completar tabla a 20–30 filas antes de RFC.

## Criterio de éxito

- Cero `FW download failed: -110` en la matriz
- Ambos UIDs (`0x8`, `0xb`) con `fw_dl_success` antes del primer `hw_params`
- Sin regresión en estéreo L/R (serie C aplicada)

## Script de recogida (recomendado)

```bash
# Tras cada boot:
~/snd_repair/scripts/fw-validation-run.sh boot [--notes "0006+0007"]

# Con prueba L/R:
~/snd_repair/scripts/fw-validation-run.sh boot-audio

# Tras suspend/resume:
~/snd_repair/scripts/fw-validation-run.sh suspend

# Matriz de rates (sin reboot):
~/snd_repair/scripts/fw-validation-run.sh rates

# Progreso:
~/snd_repair/scripts/fw-validation-run.sh status
```

Salida: `~/snd_repair/validation/{fw-matrix.csv,fw-summary.md,boot-logs/}`

Script legado: `collect-tas2783-fw.sh` → `~/tas2783-fw-matrix.log` (texto libre).

## Si falla de nuevo

- Capturar trace SoundWire (`dynamic_debug` en `soundwire/`)
- Considerar si el retry debe vivir en `soundwire/bus` en lugar del codec
