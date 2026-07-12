# Multi-client capture matrix — post-S2

**2026-07-12 15:41** · script: `scripts/capture-client-access-matrix.sh`  
**Device:** `hw:1,4` S32_LE · **context:** post-S2 · **duration:** 1 s per probe

Artifacts: `validation/capture-client-matrix-20260712-154047/`

---

## Question

Is RW failure specific to `arecord`, or does **every RW client** fail while MMAP passes?

---

## Results

| Client | Access | Verdict | Bytes | Note |
|--------|--------|---------|-------|------|
| arecord | RW | **FAIL** | 44 | EIO on `pcm_read` |
| arecord | MMAP | **PASS** | 384044 | `-M` |
| ffmpeg | RW | **FAIL** | 0 | EIO opening `hw:1,4` |
| gstreamer alsasrc | RW | **PARTIAL** | 622636 | ~1.6 s captured; pipeline timeout (no clean EOS) |

Skipped (not installed): sox, tinycap.

---

## Conclusion

**Not PipeWire-specific. Not arecord-specific.**

- All strict single-shot RW probes (**arecord**, **ffmpeg**) → **FAIL** with EIO.
- MMAP (**arecord -M**) → **PASS**.
- GStreamer RW captured data then hung — treat as **partial / different teardown path**, not a clean PASS.

Strengthens upstream narrative: determinant is **ALSA access mode**, not one userspace tool.

---

## Next

1. `capture-access-cold-vs-s2.sh --phase cold` after reboot
2. `sudo capture-rw-mmap-trace.sh` — first kernel divergence
3. Optional: install `sox`, `tinyalsa-tools` and re-run for full client grid

See [../upstream/rw-vs-mmap-post-s2-px13.md](../upstream/rw-vs-mmap-post-s2-px13.md).
