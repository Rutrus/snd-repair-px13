# Investigation summary — TAS2783 SoundWire (ASUS ProArt PX13)

> **English** | [Español](es/INVESTIGATION-SUMMARY.md)

Maintainer-facing attachment. Full log: [`../../docs/expert-report.md`](../../docs/expert-report.md).

## Platform

- **Machine:** ASUS ProArt PX13 (HN7306EAC), AMD ACP70
- **Profile:** `rt721_l1u0_tas2783x2_l1u8b` — RT721 + 2× TAS2783 (UID `0x8` Left, `0xb` Right)
- **Reference kernel:** 7.0.0 (Ubuntu)

## Timeline (summary)

| Phase | Finding |
|-------|---------|
| Initial symptom | Capture `-22`; intermittent FW `-110` on `:b`; left speaker only |
| SDW instrumentation (ENZODBG) | `sdw_program_port_params` ret=0 on AMD manager — bus not root cause |
| Patch 0004 | Capture: `source_ports` NULL in DisCo → skip `hw_params`/`hw_free` |
| FW matrix (7 boots) | `:b` fails ~50% pre-retry; 0006+0007 improve; stereo still broken |
| ENZOPLAY (0008) | Both amps on stream; `ch_mask=0x3` on both → H2 ruled out, H3 proven |
| Patch 0009 | Split `0x1`/`0x2` → **L/R validated** (`speaker-test -s1`/`-s2`) |

## Three problems — cause and fix

### A — Capture `-EINVAL` (Series A)

- **Cause:** TAS2783 speaker-only with no `source_ports` in SDW properties; shared capture dailink tries `port=2`.
- **Fix:** Do not join slave to capture stream if `!prop.source_ports`.
- **Ruled out:** `soundwire-amd` bug, wrong ACPI.

### B — Intermittent FW `-ETIMEDOUT` (Series B, experimental)

- **Cause:** Race/timing in `sdw_nwrite_no_pm()` during async download; predominant on second slave.
- **Mitigation:** Bounded retry + `wait_event` in `hw_params`.
- **Ruled out:** corrupt firmware, wrong ACPI UID.

### C — Left-only stereo (Series C)

- **Cause:** (1) `asoc_sdw_hw_params()` duplicates stereo mask in playback (`step=0`); (2) `tas2783-sdw.c` ignores `ch_maps` when calling `sdw_stream_add_slave()`.
- **Fix:** `BIT(i)` per codec when `ch == num_codecs`; honor `ch_map->ch_mask` in `port_config`.
- **Ruled out:** second codec off pipeline (H2); right hardware (H4 after fix).

## Call tree (playback, simplified)

```
machine hw_params → asoc_sdw_hw_params()     [ch_maps]
       → tas_sdw_hw_params()                  [port_config.ch_mask]
       → sdw_stream_add_slave()
machine prepare → sdw_prepare_stream()
machine trigger → sdw_enable_stream()
```

## Layers ruled out as root cause

| Layer | Reason |
|-------|--------|
| `amd_manager.c` | Master/port config coherent; ENZODBG clean |
| ACPI / DisCo | UIDs and endpoints correct; driver usage was wrong |
| SoundWire core | Transport OK; both slaves `stream_add_slave ret=0` |
| Missing second codec | ENZOPLAY: both in prepare/trigger |

## Key evidence (Problem C)

```text
Before: ch_map[0/1] ch_mask=0x3 → left-only audible
After:  ch_mask=0x1 / 0x2 → speaker-test L and R correct
```

## Upstream patches

See [`../README.md`](../README.md) — independent series A/B/C, no debug instrumentation.
