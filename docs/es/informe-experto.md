# Diagnóstico técnico — ASUS ProArt PX13 (AMD ACP70 / SoundWire)

> [English](../expert-report.md) | **Español**

> **Criterio de redacción:** se distingue entre **hechos demostrados por trazas**, **hechos verificables en código** e **interpretación probable**.
>
> **Síntesis estilo mantenedor:** [`REVISION-TECNICA.md`](REVISION-TECNICA.md) — hechos vs hipótesis, estrategia upstream (recomendado para revisores).
>
> **Estado 2026-07-09:** Problema A resuelto (0004). Problema B resuelto experimentalmente (0006+0007, Boot 7). Problema C resuelto con 0009 (estéreo L/R validado).

---

# Estado actual del diagnóstico

Investigación por **eliminación de hipótesis**: cada fase reduce el espacio de búsqueda. El foco actual está en la **capa de reproducción ASoC**, siendo el enrutamiento multicodec hacia el segundo TAS2783 la hipótesis principal (**H1**), pero aún pendiente de confirmación experimental.

## Problema A — Apertura incorrecta de capture en TAS2783

**Estado:** ✅ Resuelto experimentalmente (parche **0004**; mecanismo demostrado por trazas).

| Evidencia demostrada | Valor |
|--------------------|-------|
| `Program transport params failed: -22` | Sí (pre-0004) |
| `sdw_get_slave_dpn_prop() == NULL` | Sí |
| Puerto solicitado | `port = 2`, capture |
| DisCo TAS2783 (runtime) | Solo `sink_ports` (playback) |
| RT721 | `source_ports` correctos |

**Conclusión (vinculada log ↔ código):**

> El stream de captura intentaba incorporar un TAS2783 que, según las propiedades DisCo descubiertas en tiempo de ejecución, únicamente expone puertos `sink` para reproducción. La ausencia de un `source_dpn_prop` para `port=2` provoca el retorno `-EINVAL` en `sdw_get_slave_dpn_prop()`.

---

## Problema B — Descarga de firmware SmartAmp

**Estado:** ✅ Resuelto **experimentalmente** mediante los parches **0006 + 0007** (confirmado en Boot 7).

| Fase | Log |
|------|-----|
| Antes | `FW download failed: -110`, `playback without fw download` |
| Después (Boot 7) | FW OK en `:8` y `:b`, sin advertencias |

**Conclusión:**

> Tras Boot 7, la descarga de firmware **ya no parece ser el origen del problema de reproducción observado** (canal izquierdo audible, derecho mudo).

**Matiz (no demostrado aún):**

- Si el arreglo 0006+0007 es completamente general para todo el hardware TAS2783/SDW.
- Si ambos DSP quedan configurados correctamente tras la carga, o simplemente dejan de fallar en el bulk write.

Ampliar matriz de reboots antes de presentar 0006+0007 como fix definitivo upstream.

---

## Problema C — Solo reproduce el canal izquierdo

**Estado:** 🎯 **Activo** — único bloqueante restante para estéreo completo.

| Hecho demostrado | Estado |
|------------------|--------|
| Ambos TAS2783 enumerados | ✅ |
| Ambos cargan firmware sin error (Boot 7) | ✅ |
| Pipeline SDW funcional | ✅ |
| Audio audible (mono / izquierdo) | ✅ |
| Canal derecho audible | ❌ (no demostrado lo contrario) |

**Conclusión:**

> El problema restante pertenece ya a la **fase de reproducción ASoC** y no a la inicialización del bus SoundWire ni del firmware de los amplificadores (en el escenario Boot 7).

---

## Qué queda descartado — y qué no

### Con evidencia suficiente para descartar como causa del `-22` / transporte SDW

- Enumeración SoundWire
- Descubrimiento DisCo (como origen del error de programación de puertos en capture)
- `soundwire_amd` como origen del `-22` (instrumentación ENZODBG)
- Cálculo de `transport_params` en ruta AMD
- ACPI matching (enumeración correcta de los tres esclavos)
- PipeWire / WirePlumber como origen del fallo SDW

### Formulación más conservadora (Problema B / reproducción)

No escribir «descarga de firmware descartada» de forma absoluta. Preferir:

> La descarga de firmware **ya no parece ser el origen del problema de reproducción observado** tras Boot 7.

Queda abierto si el firmware configura ambos DSP de forma idéntica/correcta para estéreo.

### No descartado al 100 %

- **Hardware SoundWire** como causa del mute derecho (baja probabilidad; ver **H4**)
- Configuración post-FW del DSP derecho

---

## Hipótesis activas (Problema C)

Ninguna demostrada aún. Prioridad explícita:

| ID | Hipótesis | Probabilidad |
|----|-----------|--------------|
| **H1** | Routing multicodec ASoC (`soc_sdw_utils`, `acp-sdw-legacy-mach`, `codec_info_list`) | **Alta** |
| **H2** | Segundo TAS2783 no participa en el stream de reproducción (`probe → FW OK → hw_params → sin `trigger`) | Media |
| **H3** | Asignación incorrecta de `ch_mask` / channel map (mismo canal a ambos amps) | Media |
| **H4** | Problema físico del canal derecho (altavoz / cableado) | Baja — no descartado hasta prueba cruzada |

### H1 — Routing ASoC multicodec

Puntos de revisión: `soc_sdw_utils.c`, `acp-sdw-legacy-mach.c`, `codec_info_list`, `ch_mask` en `tas2783-sdw.c`.

### H2 — Segundo codec sin participación en runtime

```text
probe → FW OK → hw_params → (no trigger)
```

### H3 — Canal PCM mal asignado

```text
PCM L → Left Amp
PCM L → Right Amp
```

### H4 — Hardware canal derecho

Incluido por rigor metodológico; descartar con `speaker-test -s 2` audible o intercambio físico si fuera posible.

---

## Qué falta demostrar

| Pregunta | Evidencia necesaria |
|----------|---------------------|
| ¿Ambos codecs reciben `hw_params()`? | Instrumentación en `tas2783-sdw.c` |
| ¿Ambos reciben `trigger()`? | Instrumentación ASoC / codec |
| ¿Ambos reciben el mismo `ch_mask`? | Instrumentación `soc_sdw_utils` / `stream.c` |
| ¿El segundo codec recibe muestras PCM del canal R? | `speaker-test -s 1/-s 2` + trazas simultáneas |

Todavía **no se sabe** si `tas2783-2` (`:b`, Right): (1) no recibe PCM, (2) recibe PCM pero canal incorrecto, o (3) recibe canal correcto pero no llega a `trigger()`.

---

## Experimento prioritario

**No añadir parches** hasta completar esta comprobación.

### Por qué `speaker-test -s 1` / `-s 2`

> Permite distinguir entre un **problema de enrutamiento de canales** (H3) y un **problema de activación del segundo codec** (H2). Si el canal derecho permanece mudo incluso cuando se reproduce **exclusivamente** el canal derecho (`-s 2`), el foco pasa del firmware al dailink multicodec ASoC.

```bash
speaker-test -D plughw:1,2 -c 2 -t wav -l 1 -s 1   # solo L
speaker-test -D plughw:1,2 -c 2 -t wav -l 1 -s 2   # solo R
```

Registrar simultáneamente: `hw_params`, `prepare`, `trigger`, `stream_add_slave` en **ambos** UIDs (`:8` / `:b`).

| Resultado | Lectura |
|-----------|---------|
| `-s 1` suena, `-s 2` mudo | H1 o H2 favorecidas |
| Ambos suenan | H3/H4 menos probables; revisar dispositivo PCM |
| Ninguno | Regresión o dispositivo incorrecto |

---

## Resumen ejecutivo (detalle histórico)

La instrumentación (`ENZODBG`) permitió localizar de forma precisa el origen del error `-EINVAL (-22)` durante la preparación de streams SoundWire.

**Demostrado por trazas:** el subsistema AMD SoundWire Manager (`soundwire-amd`) **no es el origen del fallo**. Todas las funciones instrumentadas del manager finalizan con `ret=0`.

**Demostrado por trazas:** el error se produce en la ruta de programación de puertos de esclavos (`soundwire-bus`), concretamente cuando `sdw_get_slave_dpn_prop()` devuelve `NULL` para el TAS2783 en un stream de captura.

**Demostrado por trazas (histórico):** el firmware DSP podía no estar cargado antes de `hw_params()` (`error playback without fw download`).

**Actualización Boot 7:** mitigado con 0006+0007; ya no bloquea en boots exitosos.

---

# Parte I — Hechos demostrados (instrumentación ENZODBG)

## 1. SoundWire Manager AMD descartado

Trazas en `amd_sdw_transport_params()` y `amd_sdw_port_params()`:

```text
ENZODBG[4] amd_xport OK … ret=0
ENZODBG[5] amd_port OK … ret=0
ENZODBG[5] master_port OK … ret=0
```

**Conclusión demostrada:**

- ACP70 (`rev=0x70`) en ruta válida.
- Programación de transporte y puertos del master AMD correcta.
- El manager AMD no genera el `-EINVAL` observado en `Program transport params failed`.

---

## 2. Localización exacta del `-EINVAL`

Cadena demostrada:

```text
sdw_program_port_params()
    └── sdw_program_slave_port_params()
            └── sdw_get_slave_dpn_prop()
                    └── return NULL
                            └── -EINVAL (-22)
```

Identificación en runtime:

| Campo             | Valor demostrado            |
| ----------------- | --------------------------- |
| Codec             | TAS2783 (`sdw:…:01:8`)      |
| `devnum`          | 2                           |
| Dirección         | Capture (`dir=1`)           |
| Puerto solicitado | 2                           |
| Stream            | `subdevice #0-Capture`      |

Trazas:

```text
ENZODBG[3] slave_port FAIL … devnum=2 port=2 dir=1 dpn_prop NULL
ENZODBG[6] sdw_program_params ret=-22 stream=subdevice #0-Capture
Program transport params failed: -22
```

---

## 3. Causa inmediata (demostrada)

Durante la preparación del stream de **captura**, el bus intenta resolver propiedades DPN del **puerto 2** en dirección TX (capture).

El DisCo del TAS2783 (verificado previamente en sysfs) anuncia:

```text
sink_ports = 0x2   → DP1 (playback)
source_ports       → (ausente / 0)
```

Por tanto `sdw_get_slave_dpn_prop()` no encuentra `src_dpn_prop` para puerto 2 → `NULL` → `-EINVAL`.

**Esto es la causa inmediata del error**, no una inferencia.

---

## 4. Qué demuestran las trazas en conjunto

| Aspecto                         | Estado        |
| ------------------------------- | ------------- |
| Enumeración SoundWire           | OK            |
| Respuesta de esclavos           | OK            |
| Manager AMD                     | OK            |
| Playback TAS2783 (DP1, dir=0)   | OK            |
| Playback RT721                  | OK            |
| Capture RT721 (DP2)             | OK            |
| Capture TAS2783 (DP2)           | **FAIL**      |

---

## 5. Segundo problema (firmware — histórico; resuelto Boot 7)

```text
error playback without fw download
ASoC error (-22) at snd_soc_dai_hw_params() on tas2783-codec
```

Indica que `fw_dl_success == false` en el driver del codec cuando ALSA ejecuta `hw_params()`.

**Independiente** del fallo de `dpn_prop NULL` en capture. Ambos deben resolverse para audio funcional completo.

---

# Parte II — Lo que las trazas no demuestran solas

## Cadena demostrada (mecanismo del fallo)

```text
ALSA abre stream capture
    ↓
TAS2783 recibe hw_params(capture)          ← quién lo provoca: NO demostrado por trazas
    ↓
port_config.num = 2
    ↓
sdw_stream_add_slave()
    ↓
sdw_program_slave_port_params()
    ↓
sdw_get_slave_dpn_prop() → NULL
    ↓
-EINVAL
```

**No afirmar:** *"la causa raíz es un bug de topología"* — eso no está demostrado.  
**Sí afirmar:** existe un **desajuste** entre lo que el stream solicita (DP2 capture) y lo que el DisCo anuncia (solo sink DP1).

## Quién tomó la decisión equivocada — tres escenarios (no demostrados)

| Escenario | Componente | Probabilidad |
|-----------|------------|--------------|
| 1 | `tas2783-sdw`: DAI con `.capture` + `port=2` en `hw_params` | Muy probable (código verificable) |
| 2 | Machine / `sdw_utils`: TAS2783 en dailink capture (`.direction = {true,true}`) | Posible (código verificable) |
| 3 | ASoC crea stream full-duplex para codec playback-only | Menos probable |

### Evidencia en código (no sustituye trazas)

```text
sound/soc/codecs/tas2783-sdw.c
    → snd_soc_dai_driver: .capture presente
    → tas_sdw_hw_params(): port=2 en capture

sound/soc/sdw_utils/soc_sdw_utils.c
    → codec_info_list[tas2783]: .direction = {true, true}
```

Un mantenedor upstream preguntaría: *¿por qué llega aquí un `hw_params(capture)`?* — esa pregunta sigue abierta.

---

# Parte III — Arquitectura del problema

```text
                 Playback
                     │
      RT721 ───────────────► OK (port=1, dir=0)
      TAS2783 #1 ──────────► OK (port=1, dir=0)
      TAS2783 #2 ──────────► OK (port=1, dir=0)
                     │
           soundwire-amd ──► OK ([4][5][6] ret=0)


                 Capture
                     │
      RT721 ───────────────► OK (port=2, dir=1)
      TAS2783 #2 ──────────► solicita port=2, dir=1
                     │
        sdw_get_slave_dpn_prop()
                     │
             src_dpn_prop inexistente
                     │
                     ▼
                NULL → -EINVAL
```

---

# Parte IV — Hipótesis de corrección (no solución definitiva)

**No recomendado:** silenciar el error en `soundwire-bus` — el framework detecta correctamente una inconsistencia.

### Parche 0004 — hipótesis de corrección experimental

```c
if (capture && !source_ports)
    return 0;   /* no unirse al stream capture */
```

| Aspecto | Valoración |
|---------|------------|
| Utilidad | Elimina el flujo inválido; buen experimento |
| Validación runtime | Tras 0004: desaparece `Program transport params failed` en capture |
| ¿Solución upstream? | **Aún por validar** — puede no ser el sitio correcto |
| Pregunta del mantenedor | *¿Por qué llega `hw_params(capture)` aquí?* |

La solución aceptada podría estar en machine driver, ACPI/`codec_info_list`, o quitar `.capture` del DAI — no necesariamente en el guard de `hw_params`.

### Opción A — `tas2783-sdw` (donde está 0004)

Guard en `hw_params` / revisar `.capture` en el DAI.

### Opción B — machine / `sdw_utils`

`.direction = {true, false}` para TAS2783; dailink altavoces playback-only.

### Problema B — firmware (resuelto en Boot 7 con 0006+0007)

Era independiente del Problema A. Síntoma histórico:

```text
FW download failed: -110   (intermitente en :b, ~50% boots)
playback without fw download (:8 WARN por race async)
```

**Estado actual:** Boot 7 — ambos UID OK; 0006 (retry nwrite) + 0007 (wait en hw_params) aplicados. **Experimental** — confirmar en matriz ampliada.

**Problema C — routing estéreo** sustituye a firmware como foco de investigación (ver Parte VIII).

---

# Parte VII — Matriz de reinicios y separación de problemas (jul 2026)

## Metodología

Script `scripts/collect-tas2783-fw.sh` tras cada reboot; correlación con `speaker-test -D plughw:1,2 -c 2`.

Mapeo ACPI (demostrado en `amd-acp70-acpi-match.c`):

| UID SDW | Prefijo ACPI | Canal físico |
|---------|--------------|--------------|
| `0x8` | `tas2783-1` | Left |
| `0xb` | `tas2783-2` | Right |

---

## Matriz consolidada (7 boots)

| Boot | `:8` Left | `:b` Right | Audio reportado |
|------|-----------|------------|-----------------|
| 1 | WARN | **FAIL(fw)** | solo-L |
| 2 | WARN | OK | solo-L |
| 3 | WARN | OK | solo-L |
| 4 | WARN | **FAIL(fw)** | solo-L |
| 5 | WARN | **FAIL(fw)** | solo-L |
| 6 | WARN | OK | solo-L |
| **7** | **OK** | **OK** | solo-L |

### Demostrado por la matriz (boots 1–6)

1. **`:8` nunca registra `FW download failed`** — el `-110` en `sdw_nwrite` afecta solo a **`:b`** de forma intermitente (~50%).
2. **`:8` siempre `WARN(no-fw-hw_params)`** en boots 1–6 — PipeWire/ALSA llama `hw_params()` antes de que termine `request_firmware_nowait()`.
3. **solo-L con `:b` = OK** (boots 2, 3, 6) — el canal derecho mudo **no depende exclusivamente** del fallo de firmware en probe.

### Compatible con (no demostrado como causa única)

- Contención temporal en descarga FW paralela (pierde `:b`, no alterna UIDs en nwrite).
- Race PipeWire vs callback async de firmware en `:8`.

### No compatible con

- Fallo determinista siempre en `FW download failed` para el mismo UID en todos los boots (`:8` nunca falla nwrite).
- Bug profundo de `soundwire-amd` o transporte SDW.

---

## Boot 7 — cambio de naturaleza del problema

**Boot 7** (`boot_id=686521be`, tras parches **0006 + 0007**):

```text
:8 = OK
:b = OK
(sin FW download failed, sin playback without fw download)
```

### Lo que Boot 7 demuestra

1. **Ambos TAS2783 vivos:** responden por SDW, aceptan firmware, DSP inicializado.
2. **Inicialización ya no bloquea playback** en este boot.
3. **0006 + 0007 mitigan el fallo de firmware en este hardware** (confirmado en Boot 7) — arreglo **experimental**; generalidad upstream por validar.
4. **El bus SoundWire queda descartado** para la capa FW en Boot 7: enumeración, attach, transport params, port params, firmware loader — todo OK en ese escenario.

### Matiz importante

Boot 7 **separa** dos causas que antes aparecían mezcladas:

| Causa | Boots 1–6 | Boot 7 |
|-------|-----------|--------|
| Inicialización FW / timing | ✅ problema activo | ✅ resuelto |
| Routing estéreo multicodec | ✅ presente (solo-L) | ✅ **sigue presente** (solo-L) |

**Conclusión:** con FW OK en ambos amplificadores y audio aún solo-L, la investigación **deja de estar en inicialización del codec** y pasa a **cómo ASoC construye y enruta el dailink SmartAmp hacia los dos TAS2783**.

---

## Parches 0006 y 0007 (firmware — resueltos en Boot 7)

| Parche | Mecanismo | Objetivo |
|--------|-----------|----------|
| **0006** | Retry ×5, `usleep_range(10–15 ms)` en `-ETIMEDOUT`/`-EAGAIN` durante `sdw_nwrite_no_pm()` | Timeout transitorio en bulk write FW |
| **0007** | `wait_event` en `hw_params()` hasta `fw_dl_task_done` antes de rechazar | Race PipeWire vs descarga async |

**Demostrado:** Boot 7 sin errores FW ni `playback without fw`.  
**No demostrado aún:** estabilidad en N→∞ reboots (recomendable ampliar matriz).

---

# Parte VIII — Problema C: routing estéreo multicodec

> Ver **H1–H4** y tabla «Qué falta demostrar» en «Estado actual del diagnóstico».

## Síntoma

- `speaker-test` / `Front Center`: audible **solo canal izquierdo**.
- Mixers ALSA en Boot 7: `tas2783-1/2 Speaker` = 200, `Left/Right Spk` = on — **no es mute de usuario**.

## Hipótesis detalladas (↔ H1–H3)

### H1 — El canal derecho nunca entra en el stream

```text
CPU DAI
    ├── TAS2783 Left   ← ch_mask OK
    └── TAS2783 Right  ← nunca recibe ch_mask=0x2 (o mask=0x0)
```

### H3 — Ambos amplificadores reciben el mismo canal

```text
PCM L ──► Left Amp
PCM L ──► Right Amp   (duplicado; Front Center sonaría "mono")
```

### H2 — El segundo codec no se activa en runtime

Cadena posiblemente incompleta en `tas2783-2`:

```text
probe → FW OK → hw_params → stream_add_slave → port_prep
                                              ↘ trigger() nunca llega
```

Problema de dailink o configuración ASoC, no de firmware.

---

## Siguiente experimento (prioridad)

### 1. Separación L/R audible

```bash
speaker-test -D plughw:1,2 -c 2 -t wav -l 1 -s 1   # solo L
speaker-test -D plughw:1,2 -c 2 -t wav -l 1 -s 2   # solo R
```

| Resultado | Lectura |
|-----------|---------|
| `-s 1` suena, `-s 2` mudo | A o C — derecho fuera del stream o sin trigger |
| Ambos suenan | B menos probable; revisar percepción / dispositivo PCM |
| Ninguno | Regresión o dispositivo incorrecto |

### 2. Trazas durante reproducción

```bash
speaker-test -D plughw:1,2 -c 2 -t wav -l 1 &
sudo dmesg -T | grep -Ei 'tas2783|hw_params|trigger|prepare|add_slave'
cat /proc/asound/pcm
```

### 3. Si el derecho sigue mudo con FW OK — capa ASoC (no más parches FW)

| Archivo | Qué revisar |
|---------|-------------|
| `sound/soc/amd/acp/acp-sdw-legacy-mach.c` | Construcción dailink SmartAmp |
| `sound/soc/sdw_utils/soc_sdw_utils.c` | Stream multicodec, orden codecs |
| `sound/soc/codecs/tas2783-sdw.c` | `ch_mask`, `port_config`, `stream_config` |
| `codec_info_list` (tas2783) | Orden `tas2783-1` / `tas2783-2`, endpoints ACPI |

Instrumentación sugerida: `hw_params`, `stream_add_slave`, `trigger` en **ambos** UIDs con canal y `ch_mask`.

---

# Parte V — Tabla de estado del diagnóstico (actualizada)

| Hipótesis | Estado |
|-----------|--------|
| Hardware SoundWire defectuoso | ❌ Descartado |
| Enumeración / ACPI incorrecta | ❌ Descartado (enumeración OK) |
| Error en `soundwire-amd` | ❌ Descartado (instrumentación) |
| `Program transport params failed (-22)` capture TAS2783 | ✅ Resuelto (0004) |
| `sdw_get_slave_dpn_prop()` → `NULL` en capture | ✅ Mecanismo demostrado; evitado por 0004 |
| Firmware `-110` intermitente (`:b`) | ✅ Mitigado experimentalmente (0006+0007, Boot 7) |
| Configuración DSP post-FW para estéreo | ⚠️ No demostrado |
| Race `hw_params` vs FW async (`:8` WARN) | ✅ Mitigado (0007) |
| Cadena PipeWire → altavoz (mono) | ✅ Funcional |
| **Routing estéreo L+R multicodec (H1)** | 🎯 Hipótesis principal; pendiente confirmación |
| Parche mutex serialización FW | ⏸️ No prioritario tras Boot 7 |

---

# Parte VI — Evolución histórica (actualizada)

| Fase | Resultado |
| ---- | --------- |
| Hardware / enumeración | Descartado |
| ACPI / `snd-amd-sdw-acpi` | Descartado |
| PipeWire / WirePlumber | Descartado como origen SDW |
| Hipótesis AMD manager | **Descartada** (ENZODBG) |
| Mecanismo `-EINVAL` capture TAS2783 | **Demostrado** (ENZODBG) |
| Parche 0004 | Capture SDW OK |
| Matriz FW 6 boots | `:b` intermitente; solo-L persistente |
| Parches 0006 + 0007 | **FW OK ambos amps (Boot 7)** |
| Investigación actual | **Routing SmartAmp → 2× TAS2783** |

---

## Conclusión

Informe estructurado para mantenedores ALSA / AMD / TI:

| Fase | Resultado |
|------|-----------|
| **A** — capture TAS2783 | Identificado, reproducido, aislado (0004) |
| **B** — firmware SmartAmp | Resuelto **experimentalmente** (0006+0007, Boot 7; generalidad por validar) |
| **C** — estéreo multicodec | Delimitado; H1–H4; pendiente instrumentación |

Para upstream:

- **0004** — workaround capture; mecanismo `source_dpn_prop` ausente en DisCo.
- **0006+0007** — fix timing FW **experimental** (adjuntar matriz de boots; no afirmar generalidad).
- **Problema C** — hilo separado; hipótesis H1 (routing ASoC) **pendiente de confirmación** con `speaker-test -s 2` + trazas.

La investigación se apoya en instrumentación, logs y código — no en intuición. El siguiente paso natural es instrumentar `hw_params`, `prepare`, `trigger` y la construcción del dailink multicodec (**parche 0008**).

---

# Parte IX — Instrumentación playback (0008, Problema C)

**Objetivo:** demostrar si `tas2783-2` (`UID :b`) participa en el pipeline ASoC.

Trazas `ENZOPLAY[N]` (no corrige routing):

| N | Módulo | Puntos |
|---|--------|--------|
| 1 | `snd-soc-tas2783-sdw` | `set_stream`, `hw_params`, `stream_add_slave`, `stream_remove_slave`, `port_prep` |
| 2 | `snd-soc-sdw-utils` | `asoc_sdw_hw_params` (`ch_map`), `prepare`, `trigger` |

**Fase 1 (sin sudo):** `~/snd_repair/scripts/run-stereo-phase1.sh`

**Fase 2 (sudo + reboot):** `~/snd_repair/scripts/build-playback-instrumentation.sh`

**Árbol de decisión:**

- `UID :b` sin `hw_params` / `port_prep` → **H2**
- Ambos UIDs + `machine trigger` → **H1/H3**
- `ch_map[0] == ch_map[1]` con `step=0` en playback → candidato **H3** (ver `asoc_sdw_hw_params()` en código)

---

# Parte X — Resultados ENZOPLAY (2026-07-09) y foco `ch_maps`

## Demostrado por ENZOPLAY + `speaker-test` (solo izquierdo audible)

### H2 — descartada

Ambos TAS2783 en `SDW1-PIN1-PLAYBACK-SmartAmp`:

| UID | prefix | hw_params | stream_add_slave | port_prep | machine trigger |
|-----|--------|-----------|------------------|-----------|-----------------|
| `0x8` | tas2783-1 | OK | ret=0 | PRE ch_mask=0x3 | START/STOP |
| `0xb` | tas2783-2 | OK | ret=0 | PRE ch_mask=0x3 | START/STOP |

El segundo amplificador **sí participa** en el pipeline ASoC completo.

### H3 — demostrada (máscara duplicada)

```text
ch_map[0] ch_mask=0x3 step=0
ch_map[1] ch_mask=0x3 step=0
stream_add_slave uid=0x8 port=1 ch_mask=0x3
stream_add_slave uid=0xb port=1 ch_mask=0x3
```

Ambos codecs reciben **L+R** (`0x3`), no L en uno y R en el otro.

### Trazabilidad en código (4 puntos revisados)

| # | Archivo | Hallazgo |
|---|---------|----------|
| 1 | `acp-sdw-legacy-mach.c` | Asigna `codec_maps[j].cpu=0`, `codec=j`; **no** fija `ch_mask` (se rellena en runtime) |
| 2 | `soc_sdw_utils.c` → `asoc_sdw_hw_params()` | Playback: `step=0` → mismo mask a todos (*"Identical data will be sent to all codecs"*) |
| 3 | `tas2783-sdw.c` | `snd_sdw_params_to_config()` fuerza `port_config.ch_mask = GENMASK(ch-1,0)` → ignoraba `ch_maps` |
| 4 | `amd_manager.c` | Sin anomalía; master con port 1 es coherente |

### Modelo esperado vs observado

```text
Esperado:  ch0 → tas2783-1 (Left)    ch_mask=0x1
           ch1 → tas2783-2 (Right)   ch_mask=0x2

Observado: ch0+ch1 → ambos amps     ch_mask=0x3
```

### Valoración post-ENZOPLAY (sin estimaciones de probabilidad)

| Hallazgo | Estado | Base |
|----------|--------|------|
| `ch_map` / `ch_mask` duplicados en playback multicodec | Demostrado | `ch_mask=0x3` en ambos codecs, `step=0` |
| Mecanismo en `soc_sdw_utils.c` | Identificado en código | Rama playback con `step=0` |
| TAS2783 sobrescribe mapa en `snd_sdw_params_to_config()` | Demostrado | Código + trazas |
| Segundo codec fuera del stream (H2) | Descartado | Pipeline completo en ambos UIDs |
| Fallo hardware canal derecho (H4) | Descartado para routing | 0009 + `speaker-test -s 2` |
| Manejo interno de canales en DSP post-FW | **No demostrado** | No inferir sin evidencia directa |

Ver [`REVISION-TECNICA.md`](REVISION-TECNICA.md) para análisis de causa raíz y encuadre upstream.

## Parche experimental 0009 — split L/R `ch_mask`

| Archivo | Cambio |
|---------|--------|
| `soc_sdw_utils.c` | Si `playback && num_codecs>1 && ch==num_codecs` → `ch_maps[i].ch_mask = BIT(i)` |
| `tas2783-sdw.c` | Tras `snd_sdw_params_to_config`, usar `ch_map->ch_mask` del codec en `port_config` |

Compilar: `~/snd_repair/scripts/build-playback-instrumentation.sh` (incluye ambos módulos).

**Verificación esperada en ENZOPLAY:**

```text
ch_map[0] ch_mask=0x1
ch_map[1] ch_mask=0x2
stream_add_slave uid=0x8 ch_mask=0x1
stream_add_slave uid=0xb ch_mask=0x2
```

---

# Parte XI — Validación 0009 (2026-07-09, 12:58)

## Problema C — **RESUELTO**

| Prueba | Resultado auditivo | Log |
|--------|-------------------|-----|
| `speaker-test -s 1` | Solo **izquierdo** | `ch_mask=0x1` uid=0x8 |
| `speaker-test -s 2` | Solo **derecho** | `ch_mask=0x2` uid=0xb |

Pipeline completo OK: `hw_params` → `prepare ret=0` → `trigger START/STOP` en ambos codecs.

### Mecanismo establecido (dos capas)

1. `asoc_sdw_hw_params()` asignaba estéreo completo (`0x3`) a cada codec en playback con `step=0`.
2. `tas2783-sdw.c` ignoraba `ch_maps` y forzaba `GENMASK` en `port_config.ch_mask`.
3. **0009** corrige ambos → L en `:8`, R en `:b` (validado en audio y trazas).

**No se afirma:** comportamiento interno del DSP tras la carga de firmware más allá de carga exitosa y programación de puertos.

### Estado global de los tres problemas

| ID | Síntoma | Parche | Estado |
|----|---------|--------|--------|
| A | Capture TAS2783 `-22` | 0004 | ✅ Resuelto |
| B | FW download `-110` intermitente | 0006+0007 | ✅ Resuelto (experimental) |
| C | Solo altavoz izquierdo | 0009 | ✅ **Resuelto y validado** |

### Pendiente (no bloquea playback)

- `SDW1-PIN4-CAPTURE-SmartAmp`: `machine prepare ret=-22` (TAS2783 sin `source_ports` en capture dailink; 0004 cubre codec pero no el prepare a nivel máquina).
- Retirar instrumentación ENZOPLAY/ENZODBG antes de upstream.
- Generalidad de 0006/0007/0009 en otras plataformas AMD/TI — no demostrada.

---

# Parte XII — Series upstream (parches limpios)

Estrategia de envío (estilo mantenedor): [`REVISION-TECNICA.md`](REVISION-TECNICA.md).

Parches sin debug, organizados en `~/snd_repair/upstream/`:

| Serie | Contenido | Enviar |
|-------|-----------|--------|
| A | capture sin `source_ports` | Ahora |
| B | FW retry + wait (RFC) | Tras VALIDATION-TODO |
| C | `ch_map` split + tas2783 honor mask | Ahora |
| D | `docs/INVESTIGATION-SUMMARY.md` | Bajo demanda |

Ver `upstream/README.md` y `upstream/docs/PRE-SUBMIT-CHECKLIST.md`.

---

*Última actualización: 2026-07-09 — Problema C validado; series upstream preparadas.*
