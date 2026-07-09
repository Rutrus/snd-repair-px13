# TRACK B — Capture dailink `SDW1-PIN4-CAPTURE` prepare `-22`

**Prioridad:** P2  
**Bloquea:** no (playback OK)  
**Relacionado con:** mismo card ALSA `amd-soundwire`; **no** webcam

---

## Síntoma

```text
SDW1-PIN4-CAPTURE-SmartAmp: ENZOPLAY[2] machine prepare ret=-22
```

WirePlumber / ALSA intentan abrir un dailink de **capture** en los TAS2783, que en PX13 son **solo playback**.

---

## Evidencia

| Métrica | Valor |
|---------|-------|
| `capture_dailink_warn=YES` | 13/14 boots en matriz |
| Líneas `-22` por boot | ~80–120 (boots largos), ~80 (boots cortos) |
| `regression_capture=YES` | 0/14 (Serie A no regresa en criterio actual) |
| Audio L+R manual | OK en boot #1 |

---

## Causa probable

1. Topología máquina incluye link PIN4 capture → tas2783-codec.
2. Parche **0004** evita fallo en codec; el **machine driver** aún llama `prepare` y recibe `-22`.
3. UCM / perfil HiFi puede exponer dispositivo capture fantasma.

---

## Impacto usuario

- Ruido en dmesg y posible retraso en enumeración PipeWire.
- No explica Dummy Output ni FW `:8`.

---

## Investigación pendiente

- [ ] Revisar UCM brainchillz: [`tas2783.conf`](https://github.com/brainchillz/asus-proart-px13-linux-speaker-fix) — ¿nodo capture deshabilitable?
- [ ] Medir tiempo boot → Speaker visible con/sin perfil que evite PIN4
- [ ] ¿Extender Serie A al layer `asoc_sdw` machine prepare?
- [ ] Contabilizar `-22` en CSV (campo nuevo opcional)

---

## Reproducción

```bash
grep 'SDW1-PIN4-CAPTURE.*prepare ret=-22' validation/boot-logs/boot-010.log | wc -l
journalctl -k -b | grep 'SDW1-PIN4-CAPTURE'
```

---

## Criterio de cierre

- Opción A: 0× `prepare ret=-22` en boot limpio
- Opción B: documentar como **known benign** con UCM que no expone capture a userspace

---

## Referencias

- [`../../patches/0004-tas2783-skip-capture-without-source-ports.patch`](../../patches/0004-tas2783-skip-capture-without-source-ports.patch)
- [`../../upstream/series-A-capture/`](../../upstream/series-A-capture/)
- Matriz header: `capture_dailink_warn` en [`../../scripts/fw-validation-collect.sh`](../../scripts/fw-validation-collect.sh)
