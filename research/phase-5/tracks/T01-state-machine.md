# T01 — State machine (boot → Dummy)

## Goal

Replace linear timelines with an explicit **state machine**. Each edge documents: trigger, kernel callback, persisted state.

## States (draft)

```
BOOT
  → SDW_BUS_INIT
  → SLAVE_ATTACHED (:8, :b, rt721)
  → FW_DOWNLOADING
  → FW_READY (done=1, success=1)
  → STREAM_CONFIGURED (hw_params)
  → TRIGGER_ACTIVE
  → AUDIO_OK

SUSPEND_ENTRY
  → RUNTIME_SUSPEND / SYSTEM_SUSPEND
  → ACP_SUSPENDED
  → SDW_LINK_DOWN

RESUME_ENTRY
  → ACP_RESUME
  → SDW_RESET
  → SLAVE_REATTACHED?        ← unknown
  → FW_RELOAD?               ← unknown
  → FW_READY?                ← often NO for :8
  → STREAM_CONFIGURED?
  → TRIGGER?
  → AUDIO_OK | DUMMY_OUTPUT
```

## Work

1. Fill `templates/state-transition.csv` for boot #22 (OK) and resume #24 (FAIL).
2. Mark **unknown** transitions in red / `?` until T02 traces them.
3. Mermaid diagram in this file once ≥2 paths validated.

## Exit

Any transition that differs boot vs resume without documented callback → **primary investigation target**.
