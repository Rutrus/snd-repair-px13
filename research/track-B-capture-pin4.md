# Track B — Capture `SDW1-PIN4` prepare `-22`

**Prioridad:** P2 · **Bloquea altavoces:** no  
**Estado:** documentado, playback estéreo OK con Serie C  
**Relación con Track A:** ninguna causal conocida

---

## Síntoma

```
SDW1-PIN4-CAPTURE-SmartAmp: machine prepare ret=-22
```

- ~80–120 ocurrencias por boot en 13/14 entradas de matriz
- `capture_dailink_warn=YES` en cabecera de `boot-logs/`
- `regression_capture=NO` (Serie A no cuenta esto como regresión)

---

## Causa raíz (conocida)

TAS2783 en PX13 es **solo playback**. El diseño UCM/machine aún expone un dailink de **capture** en PIN4 con ambos amps. WirePlumber enumera → `prepare` falla con `-EINVAL`.

Parche **0004** evita conectar capture a nivel codec cuando no hay `source_ports`; el **machine layer** sigue intentando preparar el link.

---

## Impacto usuario

| Área | Efecto |
|------|--------|
| Playback L/R | OK (boot #1 validado manual) |
| PipeWire startup | Posible latencia / ruido en log |
| Mic / jack | vía rt721, no vía TAS2783 |

---

## Plan de investigación

### Opción B1 — UCM (userspace, bajo riesgo)

- [ ] Revisar `tas2783.conf` en brainchillz: deshabilitar sección capture / PIN4
- [ ] `alsaucm -c … list _vars` antes y después
- [ ] Medir: `grep -c 'prepare ret=-22' validation/boot-logs/boot-NNN.log`

### Opción B2 — Kernel machine (upstream)

- [ ] Extender Serie A: omitir dailink capture en machine driver si amps sin capture port
- [ ] Comparar con `upstream/series-A-capture/`

### Opción B3 — WirePlumber policy

- [ ] ¿Se puede ignorar dispositivo capture roto sin afectar Speaker?
- [ ] Perfil WP para PX13 (baja prioridad)

---

## Criterio de cierre

- `capture_dailink_warn=NO` en matriz, **o**
- Conteo `-22` < 5 por boot y sin regresión L/R

---

## Comandos

```bash
grep -c 'SDW1-PIN4-CAPTURE.*prepare ret=-22' ~/snd_repair/validation/boot-logs/boot-013.log
alsaucm -c "$(awk '/ProArtPX13/{gsub(/^[[:space:]]+/,"");print;exit}' /proc/asound/cards)" list _verbs
```

---

## Bitácora

| Fecha | Nota |
|-------|------|
| 2026-07-09 | Presente en 13/14 boots; no correlación con suspend FAIL |
