# Phase 5 proposed kernel patches

Draft patches for branch `research/suspend-lifecycle`. **Not applied to production upstream series** until T02 trace confirms H-L1 on target hardware.

## Apply order

Base tree: upstream series **A + B + C** (`scripts/apply-upstream-patches.sh`).

| Patch | Purpose | Behavior change |
|-------|---------|-----------------|
| `0001-phase5-pm-trace.patch` | `PHASE5[...]` lines in PM + FW lifecycle | **No** (observation only) |
| `0002-phase5-fw-reload-on-resume.patch` | Invalidate FW state on system sleep; re-run `tas_io_init` on resume / re-attach / first hw_params | **Yes** |

Upstream clean equivalent: [`../../upstream/series-B-firmware/0003-ASoC-tas2783-reload-firmware-after-system-sleep.patch`](../../upstream/series-B-firmware/0003-ASoC-tas2783-reload-firmware-after-system-sleep.patch)

## Build

```bash
./scripts/build-phase5-proposed.sh              # trace + fix (default)
./scripts/build-phase5-proposed.sh --trace-only # 0001 only
```

Requires `sudo` for install (same as `build-from-upstream.sh`).

## Validate after install + reboot + suspend

```bash
./scripts/phase5-resume-collect.sh --notes "post-0002" --with-matrix
journalctl -k -b 0 | grep PHASE5
./scripts/phase5-check-invariants.sh
```

## Hypothesis

**H-L1:** `tas_io_init()` / `tas2783_fw_ready()` do not run after system resume or px13 PCI reset because `hw_init==true` blocks `tas_update_status()` and PM `-110` skips `resume()`.

**0002** clears FW bookkeeping on `system_suspend` and retriggers `tas_io_init` from `resume`, `update_status`, and (last resort) `hw_params` when no async download is in flight.

## Upstream framing (T10)

SoundWire codec drivers that load FW into amp RAM must treat system sleep as invalidating FW state — same class as CS35L56 reload paths. TAS2783 currently assumes one-shot `tas_io_init` at first attach is sufficient.
