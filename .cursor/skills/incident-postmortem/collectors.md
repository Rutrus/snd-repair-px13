# Collectors and markers

## Snapshot script

```bash
./.cursor/skills/incident-postmortem/scripts/collect-snapshot.sh [outdir] [since]
```

Writes under `outdir/` (default `/tmp/snd-repair-postmortem-<timestamp>/`):

| File | Content |
|------|---------|
| `meta.txt` | host, kernel, time, uname |
| `sdw-status.txt` | SoundWire slave status |
| `snd-repair-status.txt` | `./scripts/snd-repair status` if present |
| `journal-kernel.txt` | `journalctl -k` since window (markers filtered + raw tail) |
| `dmesg-markers.txt` | dmesg grep for snd_repair / tas / rt721 / sdw |
| `wpctl-status.txt` | PipeWire graph summary |
| `pactl-cards.txt` | card profiles / ports |
| `pactl-defaults.txt` | default sink/source |
| `default-nodes.txt` | WirePlumber persisted defaults |
| `amixer-jack.txt` | jack-related controls if present |
| `pcm-status.txt` | `/proc/asound/card*/pcm*/sub*/status` |

Set `XDG_RUNTIME_DIR` / `DBUS_SESSION_BUS_ADDRESS` for the desktop user when collecting PipeWire state.

## Manual probes (minimal)

```bash
uname -r; hostnamectl --static 2>/dev/null || hostname
grep . /sys/bus/soundwire/devices/sdw:*/status
./scripts/snd-repair status
journalctl -k --since "1 hour ago" | grep -iE 'snd_repair|tas2783|rt721|soundwire|UNATTACH|fw download|-110'
wpctl status
pactl info | grep -E 'Destino|Fuente|Default'
pactl list cards | grep -E 'Perfil activo|HiFi|pro-audio|stereo|Headphones|Headset|Speaker|Mic'
cat ~/.local/state/wireplumber/default-nodes
amixer -c 1 contents 2>/dev/null | grep -A2 -i Jack
```

## Marker glossary (snd_repair overlay)

| Marker / signal | Meaning |
|-----------------|--------|
| `snd_repair resume enum kick` | 0003 immediate ping |
| `snd_repair resume enum kick delayed` + `pend=0x4` | 0003b PASS window |
| `snd_repair post-resume fw_reinit` | 0001b ran (once per wake) |
| `post-sleep playback fw_reinit failed` | 0001 path error |
| `snd_repair pcm: prepare` / `trigger_START` | PCM lifecycle (trace build) |
| SDW `Attached` ×3 | Case B closed |
| `UNATTACHED` / `-110` / `fw download wait timeout` | Case B FAIL |
| `Audio/Source` → `…Speaker__sink` | WP mic default bug |
| Profile `stereo-fallback` | HiFi missing / no capture ports |
| `pro-output-0` / `pro-output-2` | Jack HP / Speakers under pro-audio |
| `pro-input-1` / `pro-input-4` | Headset / DMIC under pro-audio |

## Forbidden recoveries (document if user attempted)

- `PX13_AFTER_SUSPEND=1` / PCI unbind of ACP audio
- Live `px13-audio-resume.service` with overlay loaded
