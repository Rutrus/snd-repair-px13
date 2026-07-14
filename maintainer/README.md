# Maintainer notes

English · read these before reviewing the kernel patch.

| Document | Purpose |
|----------|---------|
| [ROOT_CAUSE.md](ROOT_CAUSE.md) | What fails, what was ruled out |
| [DESIGN.md](DESIGN.md) | Patch state machine |
| [EXPERIMENT_SUMMARY.md](EXPERIMENT_SUMMARY.md) | One-page lab table (W-series IDs for traceability) |

---

## Full investigation branch

```bash
git checkout resolution/bruteforce
```

Contains: all experiments, W4–W8 scripts, validation snapshots, false hypotheses, long-form closure docs, and instrumented module builds.

**`main`** is the product branch only — do not expect lab scripts there.
