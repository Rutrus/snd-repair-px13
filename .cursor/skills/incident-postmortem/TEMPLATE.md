# Incident template

Save as `research/<track>/INCIDENT-YYYYMMDD-<slug>.md`. Language: **English**.

```markdown
# Incident — <one-line symptom> (YYYY-MM-DD)

**Host:** <hostname> · <SKU> · `<uname -r>`  
**Window:** <trigger time> → <observe time>  
**Overlay / build:** <snd-repair status / installed_at / patches>  
**User symptom:** <verbatim or close paraphrase>  
**Language:** English (canonical research note)

---

## Verdict

<1–3 independent failures, each one sentence. No speculation.>

---

## Evidence

### Kernel

| Check | Result |
|-------|--------|
| SDW slave status | |
| Resume kick / delayed kick | |
| 0001b / fw_reinit markers | |
| `-110` / UNATTACHED / FW timeout | present / **absent** |
| PCM lifecycle (if traced) | |

```text
<optional: 5–20 lines of journal/dmesg from the window>
```

### Userspace

| Check | Result |
|-------|--------|
| Card profile (HiFi / pro-audio / stereo-fallback) | |
| Default sink (stable name) | |
| Default source (stable name) | |
| `~/.local/state/wireplumber/default-nodes` | |
| Streams / PCM state | |
| Jack controls (if any) | |

---

## Causal chain

```text
trigger
    → …
    → ???                    ← only if evidence gap
    → witness symptom
```

---

## Recovery applied

1. <step> — result
2. …

**Reboot required?** yes / no  
**PCI reset used?** no (forbidden) / n/a

---

## Product implications

| Do | Do not |
|----|--------|
| | |

See also: <links to CASE-A / troubleshooting / scripts>
```
