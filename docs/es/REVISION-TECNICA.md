# Revisión técnica del diagnóstico

> [English](../TECHNICAL-REVIEW.md) | **Español**

Síntesis en estilo revisión de mantenedor: qué está demostrado, qué es interpretación y qué queda abierto. Para trazas y cronología completa, ver [`informe-experto.md`](informe-experto.md).

---

## Panorama

El trabajo realizado representa una progresión clara desde un problema inicialmente poco acotado hasta la identificación de una causa raíz específica respaldada por evidencia de ejecución. La investigación ha ido descartando hipótesis mediante instrumentación del kernel y validación experimental, hasta localizar el problema en la interacción entre la capa genérica de ASoC para SoundWire y el driver del TAS2783.

El resultado del parche **0009** demuestra que el hardware, el transporte SoundWire, la programación del manager AMD y el flujo PCM funcionan correctamente. El problema residía en la asignación lógica de los canales durante la construcción del flujo multicodec.

El documento separa con claridad los hechos demostrados de las hipótesis, lo que facilita tanto la revisión técnica como una futura discusión upstream.

---

## Análisis de la causa raíz (Problema C)

La validación experimental muestra que el problema aparece en la combinación de dos componentes independientes.

### 1. Comportamiento de `soc_sdw_utils.c`

Cuando el cálculo produce `step = 0`, la utilidad genérica genera el mismo `ch_map` para todos los codecs del enlace.

En un sistema estéreo con dos amplificadores, ambos reciben inicialmente:

```text
ch_mask = 0x3
```

Este comportamiento resulta válido para determinadas topologías (por ejemplo, reproducción mono duplicada o codecs que realizan la separación de canales internamente), por lo que no puede considerarse incorrecto de forma general.

Sin embargo, no cubre el caso en el que existe una correspondencia uno a uno entre:

* número de canales PCM, y
* número de codecs SoundWire.

En esa situación, la distribución natural consiste en asignar un canal independiente a cada codec.

### 2. Comportamiento de `tas2783-sdw.c`

El driver del TAS2783 tampoco utilizaba el mapa de canales calculado por la máquina.

Durante `hw_params()` reconstruía localmente el `ch_mask` mediante una máscara continua (`GENMASK(...)`), ignorando la información proporcionada por la infraestructura ASoC.

Como consecuencia, ambos amplificadores terminaban configurándose para recibir el mismo conjunto de canales.

La instrumentación confirmó este comportamiento directamente en tiempo de ejecución.

---

## Validación experimental

Tras modificar ambos componentes:

* `soc_sdw_utils.c`
* `tas2783-sdw.c`

el flujo quedó distribuido como:

```text
PCM Stereo
      │
      ├──► UID 0x8   ch_mask = 0x1
      │
      └──► UID 0xb   ch_mask = 0x2
```

La comprobación mediante:

```bash
speaker-test -s 1
speaker-test -s 2
```

demostró que:

| Prueba | Resultado |
| ------ | --------- |
| `-s 1` | únicamente canal izquierdo |
| `-s 2` | únicamente canal derecho |

Las trazas del kernel mostraron además que ambos TAS2783 recorrían correctamente toda la secuencia:

```text
hw_params → stream_add_slave → prepare → trigger
```

Con ello puede descartarse que el segundo amplificador quedase fuera del flujo de reproducción.

**No está demostrado:** configuración interna del DSP tras la carga de firmware más allá de carga exitosa y programación correcta de puertos. Evitar inferir descarte de canal en el DSP sin evidencia directa.

---

## Estrategia de envío upstream

### Serie A

Esta serie aborda un problema independiente relacionado con la apertura de streams de captura.

El comportamiento observado consiste en intentar preparar captura sobre un dispositivo que únicamente anuncia `sink_ports` en su descripción SoundWire.

La regla general que introduce el parche es coherente con la información descubierta dinámicamente por DisCo:

```text
source_ports == 0  →  no añadir el codec al stream capture
```

Es un cambio localizado y basado en capacidades anunciadas por el propio dispositivo.

No obstante, conviene estar preparado para que algún mantenedor plantee si la solución debería residir en:

* el machine driver,
* la descripción del DAI,
* o el propio driver del codec.

La evidencia recogida durante la investigación permitirá discutir cualquiera de esas alternativas.

### Serie C

Esta serie modifica dos componentes complementarios.

**Primer parche:** la utilidad genérica distribuye un canal independiente por codec cuando:

```text
número de canales PCM == número de codecs SoundWire
```

manteniendo inalterado el comportamiento existente para:

* reproducción mono,
* configuraciones donde hay más codecs que canales,
* o topologías que esperan difusión del flujo completo.

**Segundo parche:** el driver TAS2783 deja de reconstruir el `ch_mask` y utiliza el mapa calculado por la infraestructura ASoC.

Ambos cambios son complementarios:

* modificar únicamente `soc_sdw_utils` no basta, porque el codec ignoraría el mapa recibido;
* modificar únicamente el TAS2783 tampoco basta, porque seguiría recibiendo un `ch_mask = 0x3`.

La validación experimental demuestra que ambos son necesarios para obtener separación estéreo correcta.

### Serie B

La mitigación del problema de firmware debe mantenerse como **RFC**.

Los datos actuales indican que los fallos de descarga (`-110`) desaparecieron tras introducir las modificaciones experimentales, pero la muestra todavía es limitada.

Antes de proponer una solución definitiva resulta conveniente ampliar la matriz de validación con:

* múltiples reinicios,
* suspensión y reanudación,
* distintas frecuencias de muestreo,
* diferentes escenarios de carga.

Con esa información será mucho más sencillo justificar el mecanismo de reintento ante los mantenedores.

---

## Sobre el `prepare ret=-22` residual

El mensaje residual asociado a:

```text
SDW1-PIN4-CAPTURE-SmartAmp
```

no afecta al flujo de reproducción, pero indica que todavía existe un intento de construir un pipeline de captura que incluye el SmartAmp.

Dado que el TAS2783 únicamente implementa reproducción, el siguiente paso consiste en determinar por qué el machine driver sigue generando esa ruta de captura.

La revisión debería centrarse en:

```text
sound/soc/amd/acp/acp-sdw-legacy-mach.c
```

para comprobar:

* cómo se construyen los `dai_links`,
* cómo se asignan las direcciones de reproducción y captura,
* y si el TAS2783 puede excluirse de los enlaces de captura desde el origen.

Si ese comportamiento puede corregirse en la creación de la topología, el sistema quedará consistente sin necesidad de añadir comprobaciones adicionales durante `hw_params()`.

---

## Documentos relacionados

| Documento | Contenido |
|-----------|-----------|
| [`informe-experto.md`](informe-experto.md) | Informe completo, trazas ENZOPLAY |
| [`../../upstream/docs/SERIE-C-DEFENSA.md`](../../upstream/docs/SERIE-C-DEFENSA.md) | Q&A Serie C |
| [`../../upstream/docs/MAINTAINER-REVIEW.md`](../../upstream/docs/MAINTAINER-REVIEW.md) | checkpatch, destinatarios |
| [`../../upstream/SUBMISSION-PLAN.md`](../../upstream/SUBMISSION-PLAN.md) | Calendario de envío |

---

*Julio 2026 — ASUS ProArt PX13 / snd_repair*
