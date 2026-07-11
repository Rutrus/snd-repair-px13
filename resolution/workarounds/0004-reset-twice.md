# C5 — Manager reset twice

English (canonical). Track **C**.

**Goal:** first reset leaves IRQ block in bad state; second reset matches Windows or cold-boot behaviour.

**Status:** `?`

---

## Kernel change (sketch)

In `amd_manager` resume path, call manager reset sequence twice with optional `msleep()` between.

**One variable:** only add second reset; no other edits.

---

## Userspace probe (before kernel patch)

If a debugfs or module param exposes reset — use it. Otherwise kernel patch required.

---

## Result

| Run | Gap between resets | Result | Notes |
|-----|-------------------|--------|-------|
| — | — | — | |
