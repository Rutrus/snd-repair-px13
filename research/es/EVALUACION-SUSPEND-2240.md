# Evaluación suspend/resume — icono cable (22:40)

> [English](../SUSPEND-EVAL-2026-07-09-2240.md)

## Síntoma

Tras suspend: icono **cable** en bandeja → sin sonido en altavoces → estado final **Dummy**.

## Causa (3 capas)

| Capa | Qué pasa |
|------|----------|
| Kernel | PM resume `-110` en `:8`/`:b`/rt721 |
| FW | `:8 done=0` tras PCI reset; `:b` OK |
| UI | GNOME muestra **HDMI Radeon** (cable) mientras no existe sink Speaker; luego **Dummy** |

El cable **no** es audio HDMI funcionando — es el único dispositivo “wired” visible mientras falla el Coprocessor.

## Falso positivo px13

```
22:41:37  px13 → "done" (sin errores en ventana 30s)
22:41:38  arranca PipeWire
22:41:41  primer :8 done=0  ← 3 s después
```

Con `PX13_SKIP_SPEAKER_TEST=1` el script no detecta el fallo real.

## Datos

- Matriz **#23–#24**: `:8=WARN`, `:b=OK`
- `wpctl`: Dummy Output
- Log: `validation/boot-logs/boot-024.log`

## Acción

Reboot para recuperar. Serie B kernel = fix real.
