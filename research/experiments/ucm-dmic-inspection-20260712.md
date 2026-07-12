# UCM / ACP / PipeWire — input discovery inspection (2026-07-12)

English (canonical). **Before any UCM override.** Clean boot, playback functional, GNOME input missing.

---

## Question

| Case | Meaning |
|------|---------|
| **A** | UCM defines Mic → ACP/PW does not publish it |
| **B** | UCM has no internal Mic device → override needed |

---

## 1. UCM (alsaucm)

`list _devices` fails on this alsaucm build (`failed to get list _devices`). Use **`dump text`** after activating HiFi:

```bash
alsaucm -c 1 set _verb HiFi
alsaucm -c 1 dump text
```

### Active HiFi devices (verbatim structure)

```text
Verb.HiFi {
  Device.Headphones   { PlaybackPCM hw:amdsoundwire; JackControl "Headphone Jack" }
  Device.Headset      { Comment "Headset Microphone"
                        CapturePCM hw:amdsoundwire,1
                        JackControl "Headset Mic Jack" }
  Device.Speaker      { PlaybackPCM hw:amdsoundwire,2 }
}
```

**No** `Device.Mic`, **no** Internal/Digital/DMIC device.

`rt721.conf` on disk contains a conditional `SectionDevice."Mic"` → `CapturePCM hw:${CardId},4`, but it is **not present** in the active dump because:

```text
CardComponents = " cfg-amp:2 hs:rt721"
MicCodec1      = ""          (no mic: token)
MultiMicShadow = ""          (derived from MicCodec1)
If.codecmic    → false       → Mic section omitted
```

**Verdict: Case B** — UCM profile exposes **Headset only**, not internal DMIC.

---

## 2. ACP / alsa-card-profile

```bash
find /usr/share/alsa-card-profile/ -type f | grep -Ei 'ucm|profile'
grep -R "HiFi" /usr/share/alsa-card-profile/ -n
```

- No HiFi string under `alsa-card-profile/` (ACP consumes UCM directly via PipeWire).
- PipeWire device uses `api.alsa.use-acp = true`, `api.acp.auto-profile = false`.

### Active ACP profile (pw-dump, device 57)

| Index | Name | Description |
|-------|------|-------------|
| 0 | off | Apagado |
| 1 | **HiFi** | Play HiFi quality Music |
| 2 | pro-audio | Pro Audio |

Only **HiFi** active — matches UCM verb.

---

## 3. PipeWire sources

```bash
pw-cli ls Node | grep -A20 -B5 Microphone
```

| Source | ALSA path | UCM profile |
|--------|-----------|-------------|
| **Headset Microphone** | `hw:amdsoundwire,1` | `HiFi: Headset: source` |
| ASUS FHD webcam (V4L2) | v4l2 | (default `*` in wpctl) |

**No** Internal Microphone / Digital Mic node from ACP.

PW is consistent with UCM — **not Case A**.

Jack state: `Headset Mic Jack = off`, `Headphone Jack = off`.

---

## 4. `alsa.components` origin

From pw-dump / ACP:

```text
alsa.components = " cfg-amp:2 hs:rt721"
```

Kernel machine driver (`snd-acp-sdw-legacy-mach.ko`) contains format strings:

```text
 cfg-amp:%d
%s mic:dmic cfg-mics:%d
```

So the driver **can** advertise DMIC in components, but **this machine's probe/build only emits amp + headset**. No `mic:dmic` / `cfg-mics:N` in the live string.

`/proc/asound/card1/components` — **not present** on kernel 7.0.0-27 (use ACP property above).

ALSA still exposes DMIC PCM independently:

```text
01-04: acp-dmic-codec dmic-hifi-4 : capture 1
arecord -D hw:1,4 -f S32_LE …  → PASS (functional)
```

**Split:**

| Layer | DMIC |
|-------|------|
| ASoC / ALSA PCM | ✓ hw:1,4 works |
| Card components string | ✗ not advertised |
| UCM HiFi device | ✗ not defined |
| PipeWire source | ✗ not created |
| GNOME input | ✗ webcam default |

---

## KPI chain (target)

```text
arecord hw:1,4  →  PW source  →  GNOME Internal Mic  →  apps
```

Current break: **UCM HiFi** (step 2 cannot happen without UCM device).

---

## Recommended next step (override — not applied yet)

Mirror [tas2783 Speaker override](/usr/share/alsa/ucm2/conf.d/amd-soundwire/ASUSTeKCOMPUTERINC.-ProArtPX13HN7306EAC-1.0-HN7306EAC.conf) pattern:

```text
repo/ucm2/…   →  install to /usr/share/alsa/ucm2/…
```

Add `SectionDevice."Mic"` (or `Internal Mic`) with:

- `CapturePCM "hw:${CardId},4"`
- `CapturePriority` > headset or as default internal route
- No jack dependency (unlike Headset)
- Format note: hardware prefers **S32_LE** — verify ACP/PW format negotiation

**Optional kernel follow-up:** why `mic:dmic cfg-mics:N` is omitted from components (driver/topology) — separate from UCM override; override can work without fixing components string.

---

## Override applied (repo)

| Path | Role |
|------|------|
| [`ucm2/sof-soundwire/acp-dmic.conf`](../../ucm2/sof-soundwire/acp-dmic.conf) | `Device.Mic` → `hw:1,4` |
| [`scripts/install-ucm-px13.sh`](../../scripts/install-ucm-px13.sh) | install + `Define.MicCodec1 "acp-dmic"` |

```bash
sudo ./scripts/install-ucm-px13.sh
systemctl --user restart wireplumber pipewire
```

```bash
alsaucm -c 1 set _verb HiFi && alsaucm -c 1 dump text
pw-dump | jq '.[] | select(.info.props["alsa.components"]? != null) | .info.props["alsa.components"]'
wpctl status
arecord -D hw:1,4 -f S32_LE -r 48000 -c 2 -d 2 /tmp/dmic.wav
amixer -c 1 cget numid=16   # Headset Mic Jack
```
