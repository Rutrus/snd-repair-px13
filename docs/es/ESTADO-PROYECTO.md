# Estado del proyecto — ASUS ProArt PX13 (julio 2026)

> [English](../PROJECT-STATE.md) | **Español**

Documento de **estado actual** — no la fase inicial de “sin audio”.

**Equipo:** ProArt PX13 HN7306EAC · kernel `7.0.0-27-generic`  
**Matriz:** `validation/fw-matrix.csv` (20 filas, 2026-07-09)

---

## Cuatro etapas

1. **Audio básico** — brainchillz (firmware, UCM, rt721, systemd).
2. **Fallos estructurales kernel** — Problemas A/B/C (0004, 0006/0007, 0009).
3. **Validación del pipeline** — AMD → SoundWire → dos TAS2783 → estéreo en cold boot.
4. **Último bloqueo** — solo **suspend/resume**; el arranque ya no es el problema.

---

## ✅ Resuelto

- Enumeración SoundWire, TAS2783, pipeline AMD → amps.
- **Estéreo** tras cold boot (0009 + validación L/R).
- **Problema A** — capture `-22` (0004); `REGRESSION_CAPTURE=NO` en 20 boots.
- **Problema C** — `ch_mask` 0x3→0x1/0x2; H2 descartada con instrumentación.
- **FW en boot** — 0006/0007 permitieron separar FW de routing.

## ✅ Descartado

AMD, ACP, ACPI, DisCo, enumeración SDW, PipeWire como causa raíz, hardware SmartAmp roto, routing/capture/UCM para el bloqueo restante.

---

## ❌ Único problema serio: suspend/resume

```
PM resume → -110 → :8 done=0 → Dummy Output
```

`:b` suele sobrevivir · reboot recupera.

### Matriz (corregida)

| Contexto | Métrica | Valor |
|----------|---------|-------|
| Cold boot | `:b` | **20/20 OK** |
| Cold boot | Ambos UIDs OK | **9/10** filas boot |
| Suspend real | Ambos OK | **0/9** (#16 falso positivo) |

---

## Hipótesis

**H1:** el driver no restaura el SmartAmp **izquierdo** (`:8`) en **PM resume** (no en boot ni probe).

---

## Prioridad

```
Serie B → build-from-upstream → install-tas2783.ko → reboot → 3–5 suspends → matriz
```

No seguir tocando routing, capture, UCM ni PipeWire para este bloqueo.

---

## Referencias

[INSTALACION.md](INSTALACION.md) · [VALIDACION-FW.md](VALIDACION-FW.md) · [../research/PRIORITY-DEBUG.md](../research/PRIORITY-DEBUG.md)
