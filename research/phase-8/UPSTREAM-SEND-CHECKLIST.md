# Upstream send checklist

English (canonical). Send **email first**; full report as attachment. Keep the list message under ~2 minutes read time.

---

## 1. Email

| Field | Value |
|-------|--------|
| **List** | `linux-sound@vger.kernel.org` |
| **Cc** (optional) | Vijendar Mukunda, Venkata Prasad Potturu — see `MAINTAINERS` → AMD ASoC DRIVERS |
| **Subject** | `ACP70 SoundWire: s2idle resume — STAT1 set but PCI Interrupt Status clear (ASUS PX13)` |
| **Body** | [UPSTREAM-EMAIL-DRAFT.txt](UPSTREAM-EMAIL-DRAFT.txt) |

Subscribe to the list before posting if not already subscribed (vger.kernel.org list etiquette).

---

## 2. Attachments (keep email body short)

Send **separate reviewable files** — do **not** bundle a tarball.

| # | File | Notes |
|---|------|--------|
| Body | [UPSTREAM-EMAIL-DRAFT.txt](UPSTREAM-EMAIL-DRAFT.txt) | Paste into the list email |
| 1 | [UPSTREAM-REPORT.md](UPSTREAM-REPORT.md) | Main report — falsification A/B/E in **Appendix A** only |
| 2 | [0010-journal-excerpt.txt](0010-journal-excerpt.txt) | Optional short log excerpt (~10 lines) |
| 3 | IRQ snapshots | Only if asked — `validation/.state/irq-pre-suspend-20260711T191155.txt` + `irq-post-resume-20260711T191329.txt` |
| 4 | Full logs / scripts / patches | **Only on maintainer request** |

Do **not** paste long logs into the list email.

---

## 3. After list discussion

If maintainers ask for tracking: open **kernel.org Bugzilla** — component **Drivers → Sound** (or as directed). Attach same report + logs; link to list thread.

---

## 4. Local freeze

No further local experiments unless a maintainer names a specific register, bit, or resume step to test.

---

## 5. One-line pitch (for yourself)

> Reproducible case: after s2idle resume, `STAT1=ACP_SDW1_STAT` but PCI Interrupt Status stays clear and the handler never runs; driver-side hypotheses exhausted; seeking ACP70/firmware guidance.
