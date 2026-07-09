# T08 — Firmware binary analysis (read-only)

## Files (system)

```
/lib/firmware/ti/1714-1-8.bin   # left / UID :8
/lib/firmware/ti/1714-1-B.bin   # right / UID :b  (case may vary)
```

## Commands (no modification)

```bash
cmp -l /lib/firmware/ti/1714-1-8.bin /lib/firmware/ti/1714-1-B.bin | head
xxd /lib/firmware/ti/1714-1-8.bin | head
strings -n 8 /lib/firmware/ti/1714-1-*.bin
# optional: binwalk -e /lib/firmware/ti/1714-1-8.bin
```

## Questions

- Size delta? Header identical?
- Do differing bytes map to channel/calibration regions?
- Does `:8` image require longer bus settle (explain asymmetric PM fail)?

## Output

`research/phase-5/artifacts/fw-diff-summary.md` (generated, gitignored if large)

## Not in scope

- Patching or rebundling firmware blobs
- Redistribution (ASUS/TI proprietary)
