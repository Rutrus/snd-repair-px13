# Current problem state — data collection

> **English** | [Español](es/firmware-datos.md)

> **Historical document** — early investigation (partial audio, SOF topology hypotheses).  
> Superseded by [`SOLUTION.md`](SOLUTION.md) and [`TECHNICAL-REVIEW.md`](TECHNICAL-REVIEW.md). Kept for timeline reference only.

## What we knew at this stage

1. **Hardware:** ASUS ProArt PX13 (HN7306EAC) with Ubuntu 26.04
2. **Audio codec:** TAS2783 SoundWire smart amp (Texas Instruments) + RT721 for headphones
3. **Firmware extracted:** `1714-1-8.bin` and `1714-1-B.bin` correctly installed in `/usr/lib/firmware/` (~40 KB each, valid content)
4. **Partial audio:** Sound is heard but **on one channel only** (front right does not work)
5. **Mixer controls:** Four separate speaker controls exist:
   - `Left Spk`, `Right Spk` (amplifier 1)
   - `Left Spk2`, `Right Spk2` (amplifier 2)
   - All active (`Playback [on]`)
6. **PCM devices:**
   - `hw:1,0`: RT721 (headphones)
   - `hw:1,2`: TAS2783 SmartAmp (speakers)
7. **Kernel errors:**
   - `soundwire sdw-master-0-1: Program params failed: -22` (EINVAL)
   - `soundwire sdw-master-0-1: Program transport params failed: -22`

## What we do not know (at this stage)

1. **Which SOF topology** the kernel loads (no `tplg:` line seen in dmesg yet)
2. **Exact card components** (`cfg-spk:X cfg-amp:Y hs:rt721` string)
3. **Whether both TAS2783 amps actually receive signal** or the driver sends audio to one only
4. **Whether the issue is channel mapping** (right channel to wrong amp) or **wrong SOF topology**
5. **Whether a PX13-specific SOF topology exists** or a generic one is used

---

## Hypotheses (historical — partially superseded)

### Hypothesis 1: Wrong generic SOF topology
Kernel loads a generic SOF topology unaware of **two TAS2783 amps in stereo**. `Program params failed: -22` suggests invalid parameters for the hardware.

### Hypothesis 2: Inverted or missing channel map
SOF maps both channels to one amp, or right channel goes to a non-existent amp.

### Hypothesis 3: Incomplete SOF firmware for Strix Halo
ACP70 (Strix Halo) SOF may lack full dual-TAS2783 SoundWire support on this new 2025 model.

### Hypothesis 4: UCM profile routing
Minimal `tas2783.conf` defines `PlaybackChannels 2` but not how to split across two amps.

**Later investigation showed:** missing proprietary firmware and kernel ASoC bugs (Problems A/B/C) were the actual root causes. See [`SOLUTION.md`](SOLUTION.md).

---

## Expected configuration

- **Amp 1 (TAS2783-1, address 0x8):** left channel (FL)
- **Amp 2 (TAS2783-2, address 0xB):** right channel (FR)
- **SOF topology:** route FL to amp 1, FR to amp 2
- **UCM profile:** `hw:1,2` as stereo with correct channel map

## Diagnostic commands used

```bash
sudo dmesg | grep -i tplg
cat /proc/asound/card1/components
ls -la /sys/bus/soundwire/devices/ | grep tas
```
