# Resumen de investigación — TAS2783 SoundWire (ASUS ProArt PX13)

Documento adjunto para maintainers. Informe completo: `../../Opinion_experto.md`.

## Plataforma

- **Máquina:** ASUS ProArt PX13 (HN7306EAC), AMD ACP70
- **Perfil:** `rt721_l1u0_tas2783x2_l1u8b` — RT721 + 2× TAS2783 (UID `0x8` Left, `0xb` Right)
- **Kernel de referencia:** 7.0.0 (Ubuntu)

## Cronología (resumen)

| Fase | Hallazgo |
|------|----------|
| Síntoma inicial | Capture `-22`; FW `-110` intermitente en `:b`; solo altavoz izquierdo |
| Instrumentación SDW (ENZODBG) | `sdw_program_port_params` ret=0 en AMD manager — bus no culpable |
| Parche 0004 | Capture: `source_ports` NULL en DisCo → skip `hw_params`/`hw_free` |
| Matriz FW (7 boots) | `:b` falla ~50% pre-retry; 0006+0007 mejoran; estéreo sigue roto |
| ENZOPLAY (0008) | Ambos amps en stream; `ch_mask=0x3` en ambos → H2 descartada, H3 demostrada |
| Parche 0009 | Split `0x1`/`0x2` → **L/R validado** (`speaker-test -s1`/`-s2`) |

## Tres problemas — causa y fix

### A — Capture `-EINVAL` (Serie A)

- **Causa:** TAS2783 speaker-only sin `source_ports` en propiedades SDW; dailink de capture compartido intenta `port=2`.
- **Fix:** No unir el slave al stream de capture si `!prop.source_ports`.
- **Descartado:** bug en `soundwire-amd`, ACPI incorrecto.

### B — FW `-ETIMEDOUT` intermitente (Serie B, experimental)

- **Causa:** Race/timing en `sdw_nwrite_no_pm()` durante descarga async; predominante en segundo slave.
- **Mitigación:** Retry acotado + `wait_event` en `hw_params`.
- **Descartado:** firmware corrupto, UID ACPI erróneo.

### C — Estéreo solo-L (Serie C)

- **Causa:** (1) `asoc_sdw_hw_params()` duplica mask stereo en playback (`step=0`); (2) `tas2783-sdw.c` ignora `ch_maps` al llamar `sdw_stream_add_slave()`.
- **Fix:** `BIT(i)` por codec cuando `ch == num_codecs`; honorar `ch_map->ch_mask` en `port_config`.
- **Descartado:** segundo codec fuera del pipeline (H2); hardware derecho (H4 tras fix).

## Árbol de llamadas (playback, simplificado)

```
machine hw_params → asoc_sdw_hw_params()     [ch_maps]
       → tas_sdw_hw_params()                  [port_config.ch_mask]
       → sdw_stream_add_slave()
machine prepare → sdw_prepare_stream()
machine trigger → sdw_enable_stream()
```

## Capas descartadas como causa raíz

| Capa | Motivo |
|------|--------|
| `amd_manager.c` | Master/port config coherente; ENZODBG sin errores |
| ACPI / DisCo | UIDs y endpoints correctos; problema era uso del driver |
| SoundWire core | Transporte OK; ambos slaves `stream_add_slave ret=0` |
| Segundo codec ausente | ENZOPLAY: ambos en prepare/trigger |

## Evidencia clave (Problema C)

```text
Antes: ch_map[0/1] ch_mask=0x3 → solo-L audible
Después: ch_mask=0x1 / 0x2 → speaker-test L y R correctos
```

## Parches upstream

Ver `../README.md` — series A/B/C independientes, sin instrumentación de depuración.
