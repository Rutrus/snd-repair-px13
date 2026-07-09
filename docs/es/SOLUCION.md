# Cómo llegamos a la solución del audio en el ASUS ProArt PX13

> [English](../SOLUTION.md) | **Español**

**Máquina:** ASUS ProArt PX13 (HN7306EAC)  
**Fecha:** 9 de julio de 2026  
**Audiencia:** lectura general

---

## En una frase

El portátil pasó de **no tener audio en absoluto** a **estéreo funcional** en dos etapas: primero instalar el firmware propietario que faltaba; después corregir **tres fallos distintos** en el kernel Linux que solo se hicieron visibles cuando el hardware pudo arrancar.

---

## Dos etapas del proyecto

### Etapa 1 — Hacer que el hardware pudiera arrancar

**Situación inicial:** tras instalar Linux, **los altavoces integrados no funcionaban**. No era aún un problema de ALSA, SoundWire ni del reparto estéreo: el sistema **no tenía los binarios de calibración** que Texas Instruments y ASUS usan en Windows.

```
No existe el firmware propietario (1714-1-8.bin / 1714-1-B.bin)
        ↓
Los amplificadores TAS2783 no pueden inicializarse
        ↓
No hay audio
```

**Qué se hizo:**

1. Extraer los ficheros oficiales del instalador ASUS (SmartAmp TI) con Wine.
2. Copiarlos a `/usr/lib/firmware/` (`1714-1-8.bin` → izquierdo, `1714-1-B.bin` → derecho).
3. Aplicar el repositorio de reparación (`fix-px13-audio.sh` y documentación en [`01-instalacion-firmware.md`](01-instalacion-firmware.md)).

**Resultado:** el hardware **empezó a responder**. Por primera vez el kernel podía cargar firmware, enumerar los dos amplificadores y avanzar en la cadena de audio.

Sin esta etapa, la investigación del kernel **no habría sido posible**: el sistema se detenía mucho antes.

---

### Etapa 2 — Depuración del kernel (ALSA / SoundWire)

Con el firmware en su sitio, aparecieron errores **concretos** que antes quedaban ocultos: `-22`, `-110`, solo canal izquierdo… Ahí comenzó el trabajo de instrumentación, hipótesis y parches.

**Método:** reproducir el fallo → añadir trazas → descartar causas con evidencia → un arreglo cada vez.

```
Problema A — Capture → -22          → parche 0004
Problema B — Firmware → -110        → parches 0006 + 0007 (experimental)
Problema C — Solo izquierdo         → parche 0009 (reparto L/R)
```

---

## Cronología completa

| Fase | Estado |
|------|--------|
| **0. Sistema original** | Sin audio. El kernel no encontraba el firmware propietario TAS2783. |
| **1. Extracción firmware ASUS** | `1714-1-8.bin` y `1714-1-B.bin` desde el instalador oficial → `/usr/lib/firmware/`. |
| **2. Repositorio de reparación** | `fix-px13-audio.sh` — el hardware puede inicializarse. |
| **3. Investigación kernel** | Aparecen errores específicos; depuración SoundWire/ASoC. |
| **4. Problema A** | Captura inválida en amplificador solo-reproducción → parche 0004. |
| **5. Problema B** | Descarga intermitente de firmware (`-110`) → 0006 + 0007. |
| **6. Problema C** | Ambos altavoces recibían el mismo canal → 0009 → **estéreo OK**. |

---

## Los tres problemas del kernel (resumen)

### A — Ruta de grabación imposible

Los TAS2783 de este equipo **solo reproducen**; no tienen puerto de captura en hardware. El diseño del sistema los incluía en un enlace de “grabación” → error **-22**.

**Solución:** no conectarlos a flujos de captura si el hardware no lo soporta.

---

### B — Firmware del segundo amplificador, a veces

Tras reiniciar, el altavoz derecho fallaba ~50 % de las veces al cargar firmware (**-110**).

**Solución experimental:** reintentos y espera antes de reproducir. En validación con matriz de reinicios.

---

### C — Reparto de canales (solo se oía la izquierda)

Ambos amplificadores **sí participaban**, pero recibían **los dos canales a la vez**. Lo correcto es uno por altavoz.

**Solución:** repartir canal izquierdo → amp izquierdo, derecho → amp derecho. **Validado** con pruebas L/R.

---

## De dónde partimos y dónde estamos

| Antes | Ahora |
|-------|-------|
| Sin firmware propietario | Binarios ASUS instalados y reconocidos |
| Sin audio | Transporte SoundWire y enumeración OK |
| — | Eliminado `Program transport params failed: -22` (Problema A) |
| — | Mitigado `-110` en pruebas (Problema B) |
| — | **Estéreo izquierda/derecha** (Problema C) |
| — | Parches documentados para envío a mantenedores del kernel |

---

## Qué quedó descartado

- Altavoz derecho roto (funciona con el reparto correcto).
- Enumeración ACPI incorrecta.
- “El segundo amp no recibe play” (sí recibía; canal equivocado).
- Culpar solo a PipeWire o al bus AMD (fallo en capa ASoC / reparto de canales).

---

## Lección principal

1. **Primero** hace falta que el hardware tenga lo que el fabricante no incluye en Linux (firmware propietario).  
2. **Después** se pueden ver y corregir defectos del stack del kernel, que son independientes entre sí.

Mezclar “no suena” con una sola causa habría impedido ver A, B y C.

---

## Más detalle

| Documento | Contenido |
|-----------|-----------|
| `01-instalacion-firmware.md` | Extracción e instalación del firmware ASUS (Etapa 1) |
| `informe-experto.md` | Informe técnico completo |
| `REVISION-TECNICA.md` | Revisión estilo mantenedor |
| `ACTUALIZACION-KERNEL.md` | Replicar tras actualización de kernel |
| `upstream/` | Parches para kernel oficial |
| `validation/` | Estadísticas de reinicios (Problema B) |

---

*Julio 2026 — ASUS ProArt PX13 / snd_repair*
