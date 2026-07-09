# T06 — ACP70 resume (not boot EINVAL)

## Scope shift

Phase 2 ruled out ACP as **origin of capture -22**.  
Phase 5 asks: does ACP restore **identical** state after PM?

## Files

```
sound/soc/amd/acp70/*.c
sound/soc/amd/ps-sdw-dma.c
sound/soc/amd/sdw-manager*.c   (if present in tree)
sound/soc/amd/acp-common.c
```

## Compare paths

| Phase | Boot (OK) | Resume (FAIL) |
|-------|-------------|---------------|
| PCI enable | | |
| Manager init | | |
| SDW clock / frame | | |
| DMA channel state | | |
| First slave probe | | |

## Evidence hook

Journal: `PM: failed to resume: error -110` on **slave** — does manager resume return 0 before slaves fail?

```bash
journalctl -k -b 0 | rg -i 'amd.*resume|sdw.*resume|failed to resume' 
```

## Relation to px13 PCI reset

Userspace reset **replaces** a broken resume path — measure whether manager+slaves match **cold boot** or **partial warm** state after reset.
