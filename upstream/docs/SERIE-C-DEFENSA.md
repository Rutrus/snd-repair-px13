# Serie C — validación pre-envío (respuesta al mantenedor)

Documento interno. **No enviar como parche**; usar para redactar cover letter y rebuttals.

## Pregunta esperada

> ¿Por qué `snd_soc_sdw_utils` estaba equivocado para todos los codecs y no solo para TAS2783?

## Respuesta corta

No afirmamos que `step=0` sea un bug universal. Afirmamos que falta el **caso simétrico a capture** cuando `channels == num_codecs` en playback: un canal PCM por codec físico. Ese caso ya está modelado en capture; en playback se dejó siempre `step=0` por diseño original.

## Dos capas (ambas necesarias)

| Capa | Problema sin el parche | Evidencia |
|------|------------------------|-----------|
| `asoc_sdw_hw_params()` | `ch_maps[i].ch_mask = 0x3` para todos | ENZOPLAY `step=0` |
| `tas2783-sdw.c` | `snd_sdw_params_to_config()` → mask completo; ignora `ch_maps` | `include/sound/sdw.h` documenta override explícito |

**Solo tas2783** no basta: con utils sin cambiar, `ch_map->ch_mask` sigue siendo `0x3` en ambos codecs.

**Solo utils** no basta: TAS2783 programaba `port_config.ch_mask=0x3` aunque `ch_maps` fuera correcto (trazas post-0009).

## Origen histórico de `step=0`

| Hecho | Fuente |
|-------|--------|
| `asoc_sdw_hw_params()` nació en Intel `sof_sdw` con comentario *"Identical data will be sent to all codecs in playback"* | [alsa-devel msg159888](https://www.spinics.net/lists/alsa-devel/msg159888.html) |
| Lógica movida a `soc_sdw_utils.c` (AMD/Intel compartido) | [lkml 2024 — move sdw soc ops](https://lkml.indiana.edu/2408.0/00369.html) |
| Capture: reparto con `ch_mask << (i * step)` cuando `ch % num_codecs == 0` | Código actual `soc_sdw_utils.c` L1184–1203 |
| Playback: siempre `step=0` → mask idéntico | Intencional para mono duplicado a N amps |

**Conclusión:** `step=0` resolvía *mono en todos los codecs*. No contemplaba *N canales / N codecs / un altavoz por codec*.

## Precedente algorítmico (misma función)

Cuando `ch == num_codecs`, la rama capture usaría:

```text
ch_mask = GENMASK(ch / num_codecs - 1, 0)  → BIT(0)
step    = 1
ch_maps[i].ch_mask = BIT(0) << i           → BIT(i)
```

La Serie C aplica **exactamente esa máscara** en playback para el caso `ch == num_codecs`, sin tocar los demás.

## Precedentes multicodec en ASoC (no SDW)

| Patrón | Ubicación | Relevancia |
|--------|-----------|------------|
| `snd_soc_dai_set_tdm_slot(codec, 0x01)` / `0x02` por amp | `sound/soc/intel/avs/boards/ssm4567.c` | Un slot por altavoz |
| `set_tdm_slot` con mask por codec | `soc_sdw_cs_amp.c` (CS35L56 feedback) | SDW multicodec usa máscara por codec, no en utils playback |
| CPU fixup vía `ch_maps` | `soc-pcm.c` `__soc_pcm_hw_params()` | El ecosistema **confía** en `ch_maps`; el codec SDW debe alinearse |

TI TAS2783 **no** tiene `set_tdm_slot` en `soc_sdw_ti_amp.c` (solo DAPM L/R). Depende de `ch_maps` + `port_config.ch_mask`.

## Ámbito de regresión (tabla)

| Topología | `ch` | `num_codecs` | Antes | Después Serie C |
|-----------|------|--------------|-------|-----------------|
| Mono → 2 amps | 1 | 2 | `0x1` ambos | **igual** (no entra en `ch==num_codecs`) |
| Stereo → 1 amp | 2 | 1 | `0x3` | **igual** |
| Stereo → 2 amps (PX13) | 2 | 2 | `0x3` ambos | `0x1` / `0x2` ✅ validado |
| 4ch → 4 amps (MTL ACPI) | 4 | 4 | `0xf` todos | `0x1`…`0x8` — **revisado en código, no probado en HW** |
| 4ch → 2 amps | 4 | 2 | `0x3` ambos | **igual** |

Intel MTL: `tas2783_0_adr[]` con 4 dispositivos (`soc-acpi-intel-mtl-match.c`). El algoritmo escala linealmente.

## Comprobaciones pendientes antes de enviar Serie C

- [ ] Releer `git blame` / `git log` en clone git completo de torvalds/linux (el árbol local puede no ser repo git)
- [ ] Opcional: probar en hardware 4-way si disponible
- [ ] Confirmar que ningún perfil SDW usa `ch==num_codecs` en playback **esperando** duplicado stereo (búsqueda en ACPI tables multicodec)

## Orden de envío recomendado

1. **Serie A** — ahora
2. Esperar ~3–5 días / feedback
3. **Serie C** — con este documento internalizado en cover letter
4. **Serie B** — RFC + tabla de fiabilidad (ver `series-B-firmware/VALIDATION-TODO.md`)
