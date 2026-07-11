# Exit criteria — when to close the resolution lab

English (canonical). Prevents indefinite investigation. First match wins.

---

## Exit A — Stable workaround

**Condition:** One edge reaches **STABLE** (consolidation ×3) with ALSA PASS from certified S2 witness.

**Action:** Ship hook (systemd/udev); document Cost; optional narrow research re-open.

**Campaign closure:** All active campaigns → `succeeded` or `superseded`.

---

## Exit B — Upstream patch

**Condition:** Maintainer merges fix (or accepted patch series) that restores audio post-resume on PX13 class hardware.

**Action:** Archive resolution as **solved**; link patch commit in `negative/` (what *did* work).

---

## Exit C — Sufficient explanation (firmware / hardware)

**Condition:**

- Maintainer or AMD errata confirms mechanism **outside** driver fix scope (firmware, ACPI, silicon), **and**
- Negative knowledge table covers proposed software fixes, **and**
- Optional: BIOS/firmware workaround documented.

**Action:** Close campaigns C01/C02; file upstream report; stop exploration edges.

---

## Exit D — Known erratum acknowledged

**Condition:** Maintainer confirms known issue / no fix timeline / use workaround from Exit A.

**Action:** Freeze `resolution/`; maintain workaround only.

---

## Anti-goals (do not wait for)

| Trap | Why stop |
|------|----------|
| Perfect IOMMU characterization | O_IOMMU is observability — not required for Exit C if H_INTX confirmed |
| All edges PASS | L2 already closed FAIL-informative |
| Infinite fact accumulation | **Kill one big hypothesis per week** — see campaigns |

---

## Current assessment (2026-07-11)

| Exit | Status |
|------|--------|
| A | Open — no STABLE edge |
| B | Open |
| C | Partial — 0010 + negative patches strong; awaiting maintainer (C01) |
| D | Open |

**Nearest path:** C01 kill/success + C02 E07 → Exit C or A.

---

## Related

- [campaigns/README.md](../campaigns/README.md)
- [evidence/hypotheses.yaml](../evidence/hypotheses.yaml)
- [negative/rejected-fixes.yaml](rejected-fixes.yaml)
