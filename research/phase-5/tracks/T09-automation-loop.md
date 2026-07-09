# T09 — Automated resume statistics

## Goal

Move from anecdotal matrix to **rates**:

- P(fail | resume)
- Time-to-fail distribution
- Correlations: PW active, CPU load, temperature, time since boot

## Loop design

```bash
# Dry-run / manual gate — requires sudo + logged-in session
./scripts/phase5-resume-stats-loop.sh --count 20 --interval 60
```

Output: `validation/phase5-resume-stats.csv`

| run | timestamp | boot_id | pm110 | uid8_ok | uidb_ok | dummy | pw_active | load1 | notes |
|-----|-----------|---------|-------|---------|---------|-------|-----------|-------|-------|

## Safety

- Abort loop if `:8` stuck + user sets `PHASE5_ABORT=1`
- Never auto-reboot inside loop (manual recovery)
- Log each iteration with `phase5-resume-collect.sh`

## Minimum sample

- 20 resumes before drawing ordering conclusions (T05)
- 100 resumes for rate estimate (optional, overnight)
