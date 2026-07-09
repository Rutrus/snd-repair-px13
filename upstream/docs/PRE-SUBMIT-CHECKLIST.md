# Checklist pre-envío upstream

Responder **sí** a las cuatro preguntas antes de `git send-email`. Estado al 2026-07-09.

---

## Serie A — capture sin `source_ports`

| Pregunta | Respuesta |
|----------|-----------|
| **¿Genérico?** | **Sí.** Cualquier TAS2783 SDW cuyo DisCo no anuncie `source_ports` (solo `sink_ports`). No depende del DMI ASUS. |
| **¿Respeta SDW/ASoC?** | **Sí.** No intenta programar un DPN inexistente; alinea driver con propiedades runtime del slave (`sdw_slave.prop`). |
| **¿Rompe otras plataformas?** | **No** si el codec tiene `source_ports` reales (mic/feedback): el guard no actúa. Solo afecta topologías speaker-only en dailinks de capture compartidos. |
| **¿Causa en historial git?** | Comportamiento preexistente: el driver siempre asumía port 2 en capture. Revisar `git log -S source_ports -- sound/soc/codecs/tas2783-sdw.c` en árbol mainline antes del envío. |

**Madurez:** alta — enviar primero.

---

## Serie B — firmware `-110` (RFC)

| Pregunta | Respuesta |
|----------|-----------|
| **¿Genérico?** | **Parcial.** Observado en AMD ACP70 + 2× TAS2783; mecanismo (timeout en `sdw_nwrite_no_pm`) es plausible en otras topologías SDW multislave. |
| **¿Respeta SDW/ASoC?** | **Sí** como retry acotado; cuestión abierta: ¿pertenece al codec o al bus SDW? |
| **¿Rompe otras plataformas?** | Riesgo bajo (solo reintenta en `-ETIMEDOUT`/`-EAGAIN`), pero sin matriz amplia no demostrado. |
| **¿Causa en historial git?** | Investigar timing race FW async vs `hw_params`; posible interacción con enumeración multislave AMD. |

**Madurez:** experimental — ver `series-B-firmware/VALIDATION-TODO.md` (20–30 boots, S3, rates).

---

## Serie C — `ch_mask` multicodec playback

| Pregunta | Respuesta |
|----------|-----------|
| **¿Genérico?** | **Sí** para `num_codecs > 1 && ch == num_codecs` en playback. Afecta AMD ACP70 (2× TAS2783) e Intel MTL (hasta 4× en `soc-acpi-intel-mtl-match.c`). No toca el caso `step=0` intencional (mono duplicado a N codecs). |
| **¿Respeta SDW/ASoC?** | **Sí.** `snd_sdw_params_to_config()` documenta que el driver puede sobrescribir `port_config`; `ch_maps` es el mecanismo ASoC estándar (capture ya lo usaba con `step > 0`). |
| **¿Rompe otras plataformas?** | Diseños que **requieren** stereo completo en cada codec en playback (`ch != num_codecs` o un solo codec) mantienen el comportamiento anterior. |
| **¿Causa en historial git?** | `asoc_sdw_hw_params()` comentario *"Identical data will be sent to all codecs in playback"* — comportamiento deliberado para mono duplicado; la extensión para `ch == num_codecs` es la corrección mínima. |

**Madurez:** alta — **validado L/R** en PX13 (2026-07-09).

---

## Serie D — documentación

No es parche. Adjuntar `INVESTIGATION-SUMMARY.md` o `Opinion_experto.md` si el maintainer pide contexto.

---

## Orden de envío recomendado

1. **Serie A** (capture) — independiente
2. **Serie C** (channel map) — independiente de A y B
3. **Serie B** (RFC) — tras `VALIDATION-TODO.md`
4. **Serie D** — bajo demanda

## Antes de `git send-email`

- [ ] Sustituir `Signed-off-by: ASUS ProArt PX13 debug <snd-repair@local>` por tu identidad
- [ ] Rebase sobre `linux-next` o rama de mantainer
- [ ] `checkpatch.pl` en archivos tocados
- [ ] Confirmar que módulos de depuración (ENZOPLAY/ENZODBG) **no** están en el árbol enviado
