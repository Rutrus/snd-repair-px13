# T05 — Resume ordering (fine timestamps)

## Hypothesis

FW download may start while bus still not fully operational → `-110` / incomplete reload.

## Expected ordering (ideal)

```
+0 ms   PM suspend exit
+? ms   ACP / amd_manager alive
+? ms   SoundWire bus READY
+? ms   slave enumerated (:8, :b)
+? ms   FW task start (:8)
+? ms   FW task end (:8)
+? ms   first hw_params (:8)
```

## Broken ordering (suspect)

```
FW start before bus READY
hw_params before FW end
:8 FW start before :b but :b succeeds  ← asymmetry
```

## Collection

- `scripts/phase5-resume-collect.sh` → append `validation/phase5-resume-timeline.csv`
- After T02 patch: kernel `PHASE5 t=+Nms` lines

## Analysis

Plot delta distributions across N resumes (T09) — if variance is low, ordering bug is reproducible.
