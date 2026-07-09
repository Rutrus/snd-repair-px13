# T04 — Compare with other SoundWire codecs

## Goal

Philosophy comparison — **not** copy-paste patches.

## Candidate drivers (in-tree)

| Codec | FW | Multi-amp | Resume notes |
|-------|-----|-----------|--------------|
| CS35L56 | yes | often pair | `soc_sdw_cs_amp.c` |
| CS42L43 | yes | | `soc_sdw_cs42l43.c` |
| RT1318 / RT1320 | varies | | Realtek SDW amps |

## Single question

> What does that driver do on **system resume** that TAS2783 does not?

Checklist per driver:

- [ ] Re-download FW on every resume?
- [ ] Reset `fw_*` flags in `resume()`?
- [ ] `flush_work` / cancel async FW before suspend?
- [ ] Re-attach streams vs rebuild from scratch?
- [ ] Wait for bus `READY` before FW?

## Output

One-page table in this file → feeds T10 upstream framing.

## Commands

```bash
grep -rn 'system.*resume\|\.resume\s*=' linux-source-*/sound/soc/codecs/*2783* \
  linux-source-*/sound/soc/sdw_utils/soc_sdw*.c
```
