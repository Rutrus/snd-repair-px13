#!/usr/bin/env bash
# Regenerate research/phase-8/proposed/0008-irq-boundary-trace.patch
# Requires Phase 6 + 0007 irq-delivery-trace on pci-ps.c (not correlate).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

SRC="$KERNEL_SRC"
OUT="$REPO_ROOT/research/phase-8/proposed/0008-irq-boundary-trace.patch"
mkdir -p "$(dirname "$OUT")"
PS="$SRC/sound/soc/amd/ps/pci-ps.c"

[[ -f "$PS" ]] || { echo "Missing $PS" >&2; exit 1; }
grep -q 'PHASE7 ctx=acp fn=irq_handler_enter' "$PS" || {
	echo "Apply 0007 irq-delivery-trace first" >&2
	exit 1
}
grep -q 'PHASE8 ctx=acp fn=irq_stats' "$PS" && [[ "${REGEN_P8_FORCE:-0}" != "1" ]] && {
	echo "0008 already in tree — restore 0007-only pci-ps or REGEN_P8_FORCE=1" >&2
	exit 1
}

cp "$PS" "$PS.snd-repair-p8-base"

python3 <<PY
from pathlib import Path

p = Path("$PS")
t = p.read_text()

inc = '#include <linux/interrupt.h>\n'
if '#include <linux/atomic.h>' not in t:
    t = t.replace(inc, inc + '#include <linux/atomic.h>\n', 1)

c_nl = "\\n"
block = (
    "/* Phase 8 / 0008: handler invocation counter (observation only). */\n"
    "static atomic64_t snd_repair_p8_irq_handler_total;\n"
    "static atomic64_t snd_repair_p8_irq_handler_since_pm;\n"
    "static u32 snd_repair_p8_irq_last_stat0;\n"
    "static u32 snd_repair_p8_irq_last_stat1;\n"
    "\n"
    "static void snd_repair_p8_log_irq_stats(unsigned int resume_id)\n"
    "{\n"
    f'\tpr_info("PHASE8 ctx=acp fn=irq_stats resume=%u handler_total=%lld since_pm=%lld last_stat0=0x%x last_stat1=0x%x{c_nl}",\n'
    "\t\tresume_id,\n"
    "\t\t(long long)atomic64_read(&snd_repair_p8_irq_handler_total),\n"
    "\t\t(long long)atomic64_read(&snd_repair_p8_irq_handler_since_pm),\n"
    "\t\tsnd_repair_p8_irq_last_stat0, snd_repair_p8_irq_last_stat1);\n"
    "}\n"
    "\n"
)
anchor = "/* Phase 7 / 0007: IRQ delivery trace"
if "snd_repair_p8_irq_handler_total" not in t:
    t = t.replace(anchor, block + anchor, 1)

old = "\tadata = dev_id;\n\tif (!adata)\n\t\treturn IRQ_NONE;\n"
new = (
    "\tadata = dev_id;\n\tif (!adata)\n\t\treturn IRQ_NONE;\n"
    "\tatomic64_inc(&snd_repair_p8_irq_handler_total);\n"
    "\tatomic64_inc(&snd_repair_p8_irq_handler_since_pm);\n"
)
if old not in t:
    raise SystemExit("acp63_irq_handler anchor missing")
t = t.replace(old, new, 1)

old2 = (
    "\t\text_intr_stat, ext_intr_stat1,\n"
    "\t\t\tcntl0, cntl1, enb, p7_trace_pci_msi ? 1 : 0);\n"
    "\t}\n"
    "\tif (ext_intr_stat & ACP_SDW0_STAT) {\n"
)
new2 = (
    "\t\text_intr_stat, ext_intr_stat1,\n"
    "\t\t\tcntl0, cntl1, enb, p7_trace_pci_msi ? 1 : 0);\n"
    "\t\tsnd_repair_p8_irq_last_stat0 = ext_intr_stat;\n"
    "\t\tsnd_repair_p8_irq_last_stat1 = ext_intr_stat1;\n"
    "\t}\n"
    "\tif (ext_intr_stat & ACP_SDW0_STAT) {\n"
)
if "snd_repair_p8_irq_last_stat0" not in t:
    if old2 not in t:
        raise SystemExit("handler stat anchor missing")
    t = t.replace(old2, new2, 1)

old_pm = (
    "\tpr_info(\"PHASE7 ctx=acp fn=pm_resume_done resume=%u ret=%d irq=%d msi=%d"
)
if "snd_repair_p8_log_irq_stats" not in t:
    markers = [
        (
            "\t\tstat0, stat1, cntl0, cntl1, enb);\n}\n\n\nstatic void handle_acp70",
            "\t\tstat0, stat1, cntl0, cntl1, enb);\n"
            "\tsnd_repair_p8_log_irq_stats(snd_repair_phase7_acp_resume_id());\n"
            "}\n\n\nstatic void handle_acp70",
        ),
        (
            "\t\tstat0, stat1, cntl0, cntl1, enb);\n}\n\nstatic void handle_acp70",
            "\t\tstat0, stat1, cntl0, cntl1, enb);\n"
            "\tsnd_repair_p8_log_irq_stats(snd_repair_phase7_acp_resume_id());\n"
            "}\n\nstatic void handle_acp70",
        ),
    ]
    replaced = False
    for old_m, new_m in markers:
        if old_m in t:
            t = t.replace(old_m, new_m, 1)
            replaced = True
            break
    if not replaced:
        raise SystemExit("pm_resume_done anchor missing")

old_susp = (
    "static int snd_acp_suspend(struct device *dev)\n"
    "{\n"
    "\treturn acp_hw_suspend(dev);\n"
    "}"
)
new_susp = (
    "static int snd_acp_suspend(struct device *dev)\n"
    "{\n"
    "\tstruct pci_dev *pci = to_pci_dev(dev);\n"
    "\n"
    "\tatomic64_set(&snd_repair_p8_irq_handler_since_pm, 0);\n"
    f'\tpr_info("PHASE8 ctx=acp fn=pm_suspend_enter irq=%d resume=%u{c_nl}",\n'
    "\t\tpci->irq, snd_repair_phase7_acp_resume_id());\n"
    "\treturn acp_hw_suspend(dev);\n"
    "}"
)
if old_susp not in t:
    raise SystemExit("snd_acp_suspend anchor missing")
t = t.replace(old_susp, new_susp, 1)

p.write_text(t)
print("0008 markers applied to pci-ps.c")
PY

(
	cd "$SRC"
	{
		echo "From: snd-repair phase8 <snd-repair@local>"
		echo "Subject: [PATCH phase8] IRQ boundary trace (handler counter, 8.1)"
		echo ""
		diff -u "$PS.snd-repair-p8-base" "$PS" |
			sed '1s|--- .*|--- a/sound/soc/amd/ps/pci-ps.c|'
	} >"$OUT"
)
rm -f "$PS.snd-repair-p8-base"
chmod +x "$SCRIPT_DIR/phase8-irq-snapshot.sh"
echo "Wrote $OUT"
