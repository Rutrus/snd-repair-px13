# Series B validation — reproducible database

> **English** | [Español](README.es.md)

**Full guide:** [`../docs/FW-VALIDATION.md`](../docs/FW-VALIDATION.md) — install, systemd, manual mode, troubleshooting.

Directory populated by `scripts/fw-validation-collect.sh`. Do not edit the CSV by hand except for corrections.

## Layout

```
validation/
├── fw-matrix.csv      # one row per boot / test
├── fw-summary.md      # statistics (regenerated on collect)
└── boot-logs/
    ├── boot-001.log
    └── ...
```

## After each boot

Manual:

```bash
./scripts/fw-validation-run.sh boot
# with kernel/patch notes:
./scripts/fw-validation-run.sh boot --notes "0006+0007+0009"
```

### Automatic (systemd)

See **[`../docs/FW-VALIDATION.md`](../docs/FW-VALIDATION.md)** for the full instructive.

```bash
./scripts/install-fw-validation-service.sh          # boot (user) + suspend (system, sudo)
sudo ./scripts/install-fw-validation-service.sh --system
sudo ./scripts/install-fw-validation-service.sh --suspend-only   # solo suspend
sudo loginctl enable-linger "$USER"
```


## With audio test

```bash
./scripts/fw-validation-run.sh boot-audio
```

## After suspend/resume

```bash
./scripts/fw-validation-run.sh suspend
```

## Sample-rate matrix (no reboot)

```bash
./scripts/fw-validation-run.sh rates
```

## Check progress

```bash
./scripts/fw-validation-run.sh status
cat validation/fw-summary.md
```

## CSV columns

| Column | Meaning |
|--------|---------|
| `uid8_fw` / `uidb_fw` | `OK`, `WARN`, `FAIL110`, `FAIL?` |
| `left_audio` / `right_audio` | `1`/`0`/empty (only with `--audio`) |
| `regression_capture` | `YES` = Problem A codec/transport (Series A) |
| *(log)* `capture_dailink_warn` | `YES` = known `SDW1-PIN4` prepare -22 on this machine |
| `suspend_resume` | `boot` or `suspend_resume` |

## RFC goal

See `upstream/series-B-firmware/VALIDATION-TODO.md` and `upstream/SUBMISSION-PLAN.md`.
