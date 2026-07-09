# Revisión pre-envío (estilo maintainer)

Estado: 2026-07-09 — parches A/C aplican limpio sobre `linux-source-7.0.0`.

## checkpatch.pl --strict

| Parche | Resultado |
|--------|-----------|
| series-A-capture/0001 | ✅ 0 errors, 0 warnings |
| series-C-channel-map/0001 | ✅ 0 errors (commit message re-wrap) |
| series-C-channel-map/0002 | ✅ 0 errors, 0 warnings |

```bash
scripts/checkpatch.pl --strict --no-tree upstream/series-A-capture/*.patch
scripts/checkpatch.pl --strict --no-tree upstream/series-C-channel-map/*.patch
```

## Destinatarios (MAINTAINERS 7.0)

| Rol | Contacto | Serie |
|-----|----------|-------|
| alsa-devel | alsa-devel@vger.kernel.org | A, B, C |
| ASoC | Mark Brown, Liam Girdwood | A, C |
| SoundWire | Vinod Koul, Bard Liao | B, C |
| TI codecs (`sound/soc/codecs/tas2*`) | Shenghao Ding, Kevin Lu, Baojun Xu | A, B, C |
| sdw_utils (Cirrus/Intel heritage) | Charles Keepax | C |
| AMD ASoC | Vijendar Mukunda | opcional (Reported-on) |

```bash
# Ejemplo send-email (ajustar identidad y ruta kernel)
git send-email --to alsa-devel@vger.kernel.org \
  --cc shenghao-ding@ti.com --cc kevin-lu@ti.com --cc baojun.xu@ti.com \
  --cc vkoul@kernel.org --cc broonie@kernel.org \
  upstream/series-A-capture/cover-letter.txt \
  upstream/series-A-capture/0001*.patch
```

## Serie A — mensaje genérico ✅

Commit centrado en **propiedades runtime SDW** (`source_ports == 0`), no en ASUS.
Hardware solo en `Reported-on:`.

## Serie C — respuesta al maintainer

**P: ¿Por qué `soc_sdw_utils` estaba mal para todos los codecs?**

R: No estaba mal en general — `step=0` es **deliberado** para mono duplicado a N
codecs. Fallaba en el caso simétrico **capture ya resuelto**: `ch == num_codecs`
con un altavoz por codec. CS35L56 evita esto con `snd_soc_dai_set_tdm_slot()` en
`soc_sdw_cs_amp.c`; TAS2783/AMD no tienen equivalente en `soc_sdw_ti_amp.c`.

**P: ¿Por qué no solo tas2783?**

R: Tras utils, `ch_maps` sigue siendo `0x3` en ambos codecs; tas2783 solo no
basta (demostrado con ENZOPLAY). Hacen falta las dos capas.

**P: ¿Rompe 4 codecs (Intel MTL)?**

R: Condición `ch == num_codecs` → masks `BIT(0..N-1)`. ACPI MTL lista 4× TAS2783
en un link; algoritmo coherente. **No probado en hardware MTL** — decirlo en cover
letter (ya incluido).

| Escenario playback | Comportamiento |
|--------------------|----------------|
| 1 codec, stereo | Sin cambio |
| N codecs, 1 ch (mono) | Sin cambio (duplicado) |
| N codecs, ch != N | Sin cambio |
| **N codecs, ch == N** | **Nuevo: BIT(i) por codec** |

## Serie B — RFC + tabla objetiva

Matriz actual (7 boots, pre/post parches):

| Boot | UID `:8` | UID `:b` | Audio |
|------|----------|----------|-------|
| 1 | OK | FAIL(fw) | solo-L |
| 2 | OK | OK | solo-L |
| 3 | OK | WARN | solo-L |
| 4 | OK | FAIL(fw) | solo-L |
| 5 | OK | FAIL(fw) | solo-L |
| 6 | OK | OK | solo-L |
| 7 | OK | OK | solo-L → **L/R tras serie C** |

**Antes 0006+0007:** `:b` FAIL ~50% (3/6 boots con fallo FW).  
**Boot 7:** 0 FAIL; estéreo aún roto hasta serie C.

Pendiente para RFC → patch formal: `VALIDATION-TODO.md` (20–30 boots, S3, rates).

## Checklist final

- [ ] Sustituir `Signed-off-by: ASUS ProArt PX13 debug <snd-repair@local>`
- [ ] Rebase sobre `linux-next` / rama maintainer
- [ ] Confirmar ENZOPLAY/ENZODBG **no** en árbol enviado
- [ ] Enviar A y C; B como `[RFC PATCH]`
