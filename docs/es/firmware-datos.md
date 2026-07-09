## Recopilación del estado actual del problema

> [English](../firmware-data.md) | **Español**

> **Documento histórico** — investigación temprana (audio parcial, hipótesis SOF).  
> Sustituido por [`SOLUCION.md`](SOLUCION.md) y [`REVISION-TECNICA.md`](REVISION-TECNICA.md). Solo referencia de cronología.

### Lo que se sabía en esta fase

1. **Hardware:** ASUS ProArt PX13 (HN7306EAC) con Ubuntu 26.04
2. **Audio codec:** TAS2783 SoundWire smart amp (Texas Instruments) + RT721 para auriculares
3. **Firmware extraído:** Los archivos `1714-1-8.bin` y `1714-1-B.bin` están correctamente instalados en `/usr/lib/firmware/` (40KB cada uno, contenido válido)
4. **Audio funciona parcialmente:** Se escucha sonido pero **solo por un canal** (Front Right no funciona)
5. **Controles de mixer:** Existen 4 controles de speaker separados:
   - `Left Spk`, `Right Spk` (amplificador 1)
   - `Left Spk2`, `Right Spk2` (amplificador 2)
   - Todos están activos (`Playback [on]`)
6. **Dispositivos PCM:** 
   - `hw:1,0`: RT721 (auriculares)
   - `hw:1,2`: TAS2783 SmartAmp (altavoces)
7. **Errores del kernel:** 
   - `soundwire sdw-master-0-1: Program params failed: -22` (EINVAL)
   - `soundwire sdw-master-0-1: Program transport params failed: -22`

### ❓ Lo que NO SABEMOS:

1. **Qué archivo de topología SOF está cargando el kernel** (no hemos visto el mensaje `tplg:` en dmesg)
2. **Los componentes exactos de la tarjeta** (el string `cfg-spk:X cfg-amp:Y hs:rt721`)
3. **Si los dos amplificadores TAS2783 están realmente recibiendo señal** o si el driver solo está enviando audio a uno
4. **Si el problema es de mapeo de canales** (el canal derecho se envía al amplificador equivocado) o de **topología SOF incorrecta** (el firmware no sabe cómo usar ambos amplificadores)
5. **Si existe una topología SOF específica para el PX13** o si está usando una genérica

---

## 🧠 Hipótesis sobre el error:

### Hipótesis 1: Topología SOF genérica incorrecta
- **Qué pasa:** El kernel carga una topología SOF genérica que no sabe que el PX13 tiene **dos amplificadores TAS2783 en configuración estéreo**
- **Evidencia:** Los errores `Program params failed: -22` sugieren que la topología está intentando configurar parámetros inválidos para el hardware
- **Consecuencia:** Solo un amplificador recibe el canal izquierdo, el otro no recibe nada (o recibe el mismo canal)

### Hipótesis 2: Mapeo de canales invertido o faltante
- **Qué pasa:** La topología SOF mapea ambos canales al mismo amplificador, o el canal derecho se envía a un amplificador que no existe/no está inicializado
- **Evidencia:** Los controles `Left Spk`/`Right Spk` y `Left Spk2`/`Right Spk2` existen pero no sabemos si ambos amplificadores están activos
- **Consecuencia:** El amplificador 1 recibe ambos canales (o solo el izquierdo), el amplificador 2 no recibe nada

### Hipótesis 3: Firmware SOF incompleto para Strix Halo
- **Qué pasa:** El firmware SOF para AMD ACP70 (Strix Halo) no tiene soporte completo para configuración de dos amplificadores TAS2783 en SoundWire
- **Evidencia:** El PX13 es un modelo muy nuevo (2025) y el soporte de Linux para Strix Halo aún está en desarrollo
- **Consecuencia:** El driver puede inicializar los amplificadores pero no puede configurar la topología de audio correctamente

### Hipótesis 4: Problema de ruteo en el perfil UCM
- **Qué pasa:** El perfil UCM `tas2783.conf` define `PlaybackChannels 2` pero no especifica cómo mapear los canales a los dos amplificadores
- **Evidencia:** El perfil es "minimal" según los comentarios del script
- **Consecuencia:** ALSA/PipeWire no sabe cómo distribuir los canales entre los dos amplificadores

---

## 🎯 Hipótesis sobre el funcionamiento esperado:

### Configuración ideal:
- **Amplificador 1 (TAS2783-1, dirección 0x8):** Recibe canal izquierdo (FL)
- **Amplificador 2 (TAS2783-2, dirección 0xB):** Recibe canal derecho (FR)
- **Topología SOF:** Configura el bus SoundWire para enviar FL al amplificador 1 y FR al amplificador 2
- **Perfil UCM:** Define que `hw:1,2` es un dispositivo estéreo con mapeo correcto de canales

### Estado actual:
- **Amplificador 1:** Recibe audio (suena el altavoz izquierdo)
- **Amplificador 2:** No recibe audio o recibe el mismo canal que el amplificador 1
- **Resultado:** Audio mono o solo canal izquierdo

---

## 🔍 Próximos pasos para confirmar la hipótesis:

Necesitamos saber:
1. **Qué topología SOF está cargando** → `sudo dmesg | grep -i tplg`
2. **Los componentes de la tarjeta** → `cat /proc/asound/card1/components`
3. **Si ambos amplificadores están inicializados** → `ls -la /sys/bus/soundwire/devices/ | grep tas`

Con esa información podremos confirmar si es un problema de topología SOF (Hipótesis 1 o 3) o de mapeo de canales (Hipótesis 2 o 4).
