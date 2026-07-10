# 0005 — S1/S2 bisect (minimal)

English (canonical). Applies on [0004](0004-phase6-amd-minimal-irq-trace.patch).

**Single question:** after `irq_enabled`, is there a pending interrupt in `ACP_EXTERNAL_INTR_STAT`, and does `acp63_irq_handler` run?

## Three probes (~25 lines)

| fn | File | When |
|----|------|------|
| `intr_stat_post_enable` | `amd_manager.c` | `readl(ACP_EXTERNAL_INTR_STAT(instance))` after enable |
| `irq_handler_enter` | `pci-ps.c` | first line after `readl(ACP_EXTERNAL_INTR_STAT)` |
| `irq_thread_enter` | `amd_manager.c` | first line of `amd_sdw_irq_thread` |

No `ping_status`. Keep 0004 `ping_irq`/`queue_work` as downstream witnesses only.

## Decision matrix

| intr_stat | irq_handler_enter | Verdict |
|-----------|-------------------|---------|
| `0` | NO | **S1** — no hardware event |
| `≠0` | NO | **S2** — event present, not delivered to handler |
| `≠0` | YES, no `irq_thread_enter` | post-ISR / workqueue |
| YES thread | — | bisect SDW path (rare on current FAILs) |
| `0` | YES | instrumentation bug |

Patch: [0005-phase6-s1-s2-bisect.patch](0005-phase6-s1-s2-bisect.patch)

```bash
./scripts/build-phase6-amd-trace.sh   # applies 0003+0004+0005
sudo reboot
./scripts/phase6-experiment.sh arm --notes run-13-s1s2
systemctl suspend
./scripts/phase6-experiment.sh sm
```
