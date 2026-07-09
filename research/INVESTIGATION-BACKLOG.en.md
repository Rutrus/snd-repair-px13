# Investigation backlog — PX13 snd_repair

> **English** | [Español](INVESTIGATION-BACKLOG.md)  
> **Quantitative snapshot:** [`FAILURE-REPORT-2026-07-09.md`](FAILURE-REPORT-2026-07-09.md)

Deferred investigation tracks. Each track has a checklist, repro commands, and closure criteria.

| Track | Topic | Related to audio suspend? | Priority |
|-------|-------|---------------------------|----------|
| [A](tracks/TRACK-A-SUSPEND-FW.md) | TAS2783 FW `:8` / PM `-110` on resume | Core issue | P0 |
| [B](tracks/TRACK-B-CAPTURE-DAILINK.md) | `SDW1-PIN4` capture prepare `-22` | Same ALSA card | P2 |
| [C](tracks/TRACK-C-WEBCAM-MEDIA0.md) | Webcam `/dev/media0`, dma-buf | **No** — separate line | P3 |
| [D](tracks/TRACK-D-PIPEWIRE-PM.md) | PipeWire / `px13-audio-fix` | Aggravates A | P1 |
| [E](tracks/TRACK-E-SYSTEMD-VALIDATION.md) | FW validation systemd units | No | P3 |
| [F](tracks/TRACK-F-ACPI-GPP4.md) | ACPI `GPP4 AE_ALREADY_EXISTS` | Speculative | P4 |

**Rule:** Do not mix Track C (webcam) into Series B RFC unless logs show correlation with Track A.

See [INVESTIGATION-BACKLOG.md](INVESTIGATION-BACKLOG.md) for the full index (Spanish).
