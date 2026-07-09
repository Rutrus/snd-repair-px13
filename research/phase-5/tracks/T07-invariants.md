# T07 — Invariants

## Definitions

```yaml
# templates/invariants.yaml
invariants:
  - id: I1
    rule: "If :8 fw_dl_task_done=1 and fw_dl_success=1 → Speaker sink exists"
    query: "wpctl + dmesg playback without fw"
  - id: I2
    rule: "If Speaker missing → :8 done=0 or fw_dl_success=0"
  - id: I3
    rule: "If :8 fails → :b still OK (asymmetric)"
  - id: I4
    rule: "If PM -110 on :8 → :8 done=0 before first hw_params"
```

## Test matrix

| Boot/resume id | I1 | I2 | I3 | I4 | Notes |
|----------------|----|----|----|----|-------|
| boot #22 | ✓ | ✓ | ✓ | n/a | |
| resume #24 | ✗ | ✓ | ✓ | ✓ | pre-0003; px13 false OK |
| resume #30 | ✓ | ✓ | ✓ | ✓ | post-0003; first OK |
| resume #31–35 | ✓ | ✓ | ✓ | ✓ | 5/5 consecutive OK |
| **post-0003 total** | **6/6** | **6/6** | **6/6** | **6/6** | matrix #30–35 |

## Script

```bash
./scripts/phase5-check-invariants.sh
./scripts/phase5-resume-collect.sh --notes N [--with-matrix]   # after each suspend
```

Breaking any **always** invariant → new track or revised state machine (T01).
