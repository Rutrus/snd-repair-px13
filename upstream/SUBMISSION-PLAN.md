# Plan de envío upstream

## Matriz de madurez (acordada)

| Serie | Madurez | Riesgo | Acción |
|-------|---------|--------|--------|
| A — `source_ports` | ⭐⭐⭐⭐⭐ | Muy bajo | **Enviar** |
| B — FW `-110` | ⭐⭐☆☆☆ | Medio/alto | **Esperar** (RFC + matriz) |
| C — `ch_map` | ⭐⭐⭐⭐☆ | Medio | Enviar tras validación adicional |

## Calendario sugerido

| Día | Acción |
|-----|--------|
| D0 | `checkpatch.pl --strict` Serie A ✅ (hecho 2026-07-09) |
| D0 | `git send-email` **Serie A** |
| D0–D5 | Extend Series C validation (`docs/SERIE-C-DEFENSE.md` checklist) |
| D0–D30 | Matriz Serie B: 20–30 boots, S3, rates |
| D5+ | **Serie C** (no el mismo día que A) |
| Tras matriz B | RFC Serie B |

## checkpatch (2026-07-09)

```text
series-A-capture/0001-*.patch     → 0 errors, 0 warnings
series-C-channel-map/0001-*.patch → 0 errors, 0 warnings
series-C-channel-map/0002-*.patch → 0 errors, 0 warnings
```

## Destinatarios (MAINTAINERS 7.0.0)

| Rol | Contacto |
|-----|----------|
| Lista principal | alsa-devel@vger.kernel.org |
| ASoC | Mark Brown \<broonie@kernel.org\>, Liam Girdwood \<lgirdwood@gmail.com\> |
| SoundWire | Vinod Koul \<vkoul@kernel.org\>, Bard Liao \<yung-chuan.liao@linux.intel.com\> |
| TI codecs (tas2783) | Shenghao Ding, Kevin Lu, Baojun Xu @ti.com |
| AMD ASoC (reported-on) | Vijendar Mukunda @amd.com (opcional CC Serie A) |
| Intel SDW utils history | Bard Liao, Peter Ujfalusi (opcional CC Serie C) |
| Cirrus SDW utils | Charles Keepax (opcional CC Serie C) |

## Serie B — plantilla tabla fiabilidad

Completar tras `~/snd_repair/scripts/summarize-fw-matrix.sh`:

| Fase | Boots | UID `:8` OK | UID `:b` OK | FW `-110` |
|------|-------|-------------|-------------|-----------|
| Sin 0006+0007 | 7 | ?/7 | ?/7 | ~50% `:b` |
| Con 0006+0007 | 7 | 7/7 | ?/7 | mejorado |
| Meta pre-RFC | 20–30 | | | 0 objetivo |

Datos en `~/snd_repair/validation/fw-matrix.csv` — ver `validation/README.md`.

## Archivos clave

- `series-A-capture/send-email.txt` — borrador envío A
- `docs/SERIE-C-DEFENSE.md` — Series C maintainer rebuttal (ES: `docs/es/SERIE-C-DEFENSA.md`)
- `docs/PRE-SUBMIT-CHECKLIST.md` — 4 preguntas por serie
- `docs/INVESTIGATION-SUMMARY.md` — Serie D bajo demanda
