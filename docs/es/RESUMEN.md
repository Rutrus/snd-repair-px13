# Audio ASUS ProArt PX13 — resumen en una página

> [English](../SUMMARY.md) | **Español**

**Equipo:** ProArt PX13 (HN7306EAC) · **Fecha:** julio 2026

---

## Punto de partida

En Linux **no sonaban los altavoces integrados**. La causa inicial no era el kernel: **faltaba el firmware propietario de calibración** de los amplificadores TI TAS2783 (`1714-1-8.bin` y `1714-1-B.bin`), que en Windows va dentro del instalador ASUS.

## Etapa 1 — Poner el hardware en marcha

1. Extraer los `.bin` del driver oficial ASUS (Wine).  
2. Instalarlos en `/usr/lib/firmware/`.  
3. Ejecutar `fix-px13-audio.sh` (ver [`01-instalacion-firmware.md`](01-instalacion-firmware.md)).

→ El audio **empezó a avanzar**; sin esto no se habría podido depurar nada más.

## Etapa 2 — Tres fallos del kernel (tras tener firmware)

| Problema | Síntoma | Solución |
|----------|---------|----------|
| **A** | Error -22 (captura imposible) | No usar TAS2783 en rutas de grabación |
| **B** | A veces -110 al reiniciar | Reintentos + espera (en validación) |
| **C** | Solo altavoz izquierdo | Repartir canal L/R entre los dos amps |

→ **Estéreo validado** (izquierda y derecha por separado).

## Resultado global

De **sin audio** a: firmware instalado, SoundWire OK, sin -22, estéreo funcional, parches preparados para el kernel Linux.

## Documentación

`SOLUCION.md` · `informe-experto.md` · `upstream/` · `ACTUALIZACION-KERNEL.md`
