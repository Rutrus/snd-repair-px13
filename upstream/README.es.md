# Parches upstream — ASUS ProArt PX13 / TAS2783 SoundWire

> [English](README.md) | **Español**

Cuatro series **independientes**. **No enviar A y C el mismo día.**

| Serie | Problema | Directorio | Enviar |
|-------|----------|------------|--------|
| A | Capture sin `source_ports` | `series-A-capture/` | **Ahora** |
| C | `ch_mask` multicodec | `series-C-channel-map/` | Tras `docs/SERIE-C-DEFENSA.md` |
| B | FW `-110` | `series-B-firmware/` | RFC + matriz 20–30 boots |
| D | Investigación | `docs/` | Bajo demanda |

Ver **`SUBMISSION-PLAN.md`** para calendario, destinatarios y checkpatch.

## Aplicación (sobre árbol vanilla, p. ej. linux 6.15+ / 7.0)

```bash
KERNEL=/ruta/a/linux
cd "$KERNEL"

git am ~/snd_repair/upstream/series-A-capture/*.patch
git am ~/snd_repair/upstream/series-C-channel-map/*.patch
git am ~/snd_repair/upstream/series-B-firmware/*.patch
```

**Dependencias entre series:** ninguna obligatoria.

Regenerar diffs: `~/snd_repair/scripts/generate-upstream-patches.sh`

## Destinatarios sugeridos

- **A, C:** `alsa-devel@vger.kernel.org`, CC Senthil Kumaran S (TI), Charles Keepax (Cirrus/sdw_utils)
- **B:** `[RFC PATCH]` hasta completar matriz de boots

## Documentación (Serie D)

- `docs/INVESTIGATION-SUMMARY.md`
- `docs/PRE-SUBMIT-CHECKLIST.md`
- `docs/MAINTAINER-REVIEW.md`
- [`../docs/es/REVISION-TECNICA.md`](../docs/es/REVISION-TECNICA.md) — revisión estilo mantenedor
- [`../docs/es/informe-experto.md`](../docs/es/informe-experto.md) — informe completo
