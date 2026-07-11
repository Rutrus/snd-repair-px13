#!/usr/bin/env bash
# Regenerate 0007-correlate.patch (t_ms export, cntl_write logs).
# Requires 0006b + 0007 already in tree (or applies via build-phase7 irq-stat-correlate).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

SRC="$KERNEL_SRC"
OUT="$REPO_ROOT/research/phase-7/proposed/0007-correlate.patch"
AMD="$SRC/drivers/soundwire/amd_manager.c"
PS="$SRC/sound/soc/amd/ps/pci-ps.c"
PSC="$SRC/sound/soc/amd/ps/ps-common.c"

for f in "$AMD" "$PS" "$PSC"; do
	[[ -f "$f" ]] || { echo "Missing $f" >&2; exit 1; }
done

grep -q 'PHASE7 ctx=acp fn=irq_handler_enter' "$PS" || {
	echo "Apply 0007 first (irq-delivery-trace)" >&2; exit 1
}
grep -q 'snd_repair_phase7_intr_decode' "$AMD" || {
	echo "Apply 0006b first (stat-decode)" >&2; exit 1
}

cp "$AMD" "$AMD.snd-repair-corr-base"
cp "$PS" "$PS.snd-repair-corr-base"
cp "$PSC" "$PSC.snd-repair-corr-base"

python3 <<'PY'
from pathlib import Path

amd = Path("/home/rutrus/snd_repair/linux-source-7.0.0/drivers/soundwire/amd_manager.c")
ps = Path("/home/rutrus/snd_repair/linux-source-7.0.0/sound/soc/amd/ps/pci-ps.c")
psc = Path("/home/rutrus/snd_repair/linux-source-7.0.0/sound/soc/amd/ps/ps-common.c")

# --- amd_manager: export t_ms + cntl_write log ---
t = amd.read_text()
export_fn = """
/* Phase 7 correlate: shared t_ms since manager_reset (instance index). */
s64 snd_repair_phase7_t_mgr_reset_ms(unsigned int instance)
{
\tif (instance >= AMD_PHASE6_MAX_LINKS ||
\t    !ktime_to_ns(amd_phase6_reset_ts[instance]))
\t\treturn -1;
\treturn ktime_to_ms(ktime_sub(ktime_get_boottime(),
\t\t\t\t     amd_phase6_reset_ts[instance]));
}
EXPORT_SYMBOL_GPL(snd_repair_phase7_t_mgr_reset_ms);

"""
if "snd_repair_phase7_t_mgr_reset_ms" not in t:
    anchor = "static void amd_phase6_mark_reset(struct amd_sdw_manager *amd_manager)\n"
    t = t.replace(anchor, export_fn + anchor, 1)

old_en = (
    "\tval = sdw_manager_reg_mask_array[amd_manager->instance];\n"
    "\tamd_updatel(amd_manager->acp_mmio, ACP_EXTERNAL_INTR_CNTL(amd_manager->instance), val, val);\n"
    "\tmutex_unlock(amd_manager->acp_sdw_lock);\n"
)
new_en = (
    "\tval = sdw_manager_reg_mask_array[amd_manager->instance];\n"
    "\tamd_updatel(amd_manager->acp_mmio, ACP_EXTERNAL_INTR_CNTL(amd_manager->instance), val, val);\n"
    "\tdev_info(amd_manager->dev,\n"
    "\t\t \"PHASE7 ctx=amd fn=cntl_write who=amd_manager inst=%u mask=0x%x cntl_after=0x%x t_ms=%lld\\n\",\n"
    "\t\t amd_manager->instance, val,\n"
    "\t\t readl(amd_manager->acp_mmio +\n"
    "\t\t       ACP_EXTERNAL_INTR_CNTL(amd_manager->instance)),\n"
    "\t\t (long long)amd_phase6_since_reset_ms(amd_manager));\n"
    "\tmutex_unlock(amd_manager->acp_sdw_lock);\n"
)
if old_en not in t:
    raise SystemExit("amd_enable_sdw_interrupts anchor missing")
t = t.replace(old_en, new_en, 1)
amd.write_text(t)

# --- ps-common: host wake cntl1 write ---
t = psc.read_text()
old_wake = (
    "\text_intr_cntl1 = readl(acp_base + ACP_EXTERNAL_INTR_CNTL1);\n"
    "\text_intr_cntl1 |= ACP70_SDW_HOST_WAKE_MASK;\n"
    "\twritel(ext_intr_cntl1, acp_base + ACP_EXTERNAL_INTR_CNTL1);\n"
)
new_wake = (
    "\t{\n"
    "\t\tu32 old_cntl1 = readl(acp_base + ACP_EXTERNAL_INTR_CNTL1);\n"
    "\n"
    "\t\text_intr_cntl1 = old_cntl1 | ACP70_SDW_HOST_WAKE_MASK;\n"
    "\t\twritel(ext_intr_cntl1, acp_base + ACP_EXTERNAL_INTR_CNTL1);\n"
    "\t\tpr_info(\"PHASE7 ctx=acp fn=cntl1_write who=acp70_host_wake old=0x%x new=0x%x\\n\",\n"
    "\t\t\told_cntl1, ext_intr_cntl1);\n"
    "\t}\n"
)
if old_wake not in t:
    raise SystemExit("acp70_enable_sdw_host_wake anchor missing")
t = t.replace(old_wake, new_wake, 1)
psc.write_text(t)

# --- pci-ps: extern t_mgr_ms in handler logs ---
t = ps.read_text()
if "snd_repair_phase7_t_mgr_reset_ms" not in t:
    inc = '#include "acp63.h"\n'
    t = t.replace(inc, inc + "\nextern s64 snd_repair_phase7_t_mgr_reset_ms(unsigned int instance);\n", 1)

def add_t_mgr_ms(line_pat, insert):
    global t
    if insert in t:
        return
    # append t_mgr_ms before closing newline of pr_info format
    pass

# irq_handler_enter line
old = (
    "\t\tpr_info(\"PHASE7 ctx=acp fn=irq_handler_enter irq=%d resume=%u stat0=0x%x stat1=0x%x cntl0=0x%x cntl1=0x%x enb=0x%x msi=%d\\n\",\n"
    "\t\t\tirq, snd_repair_phase7_acp_resume_id(), ext_intr_stat, ext_intr_stat1,\n"
    "\t\t\tcntl0, cntl1, enb, p7_trace_pci_msi ? 1 : 0);\n"
)
new = (
    "\t\tpr_info(\"PHASE7 ctx=acp fn=irq_handler_enter irq=%d resume=%u t_mgr_ms=%lld stat0=0x%x stat1=0x%x cntl0=0x%x cntl1=0x%x enb=0x%x msi=%d\\n\",\n"
    "\t\t\tirq, snd_repair_phase7_acp_resume_id(),\n"
    "\t\t\t(long long)snd_repair_phase7_t_mgr_reset_ms(1),\n"
    "\t\t\text_intr_stat, ext_intr_stat1,\n"
    "\t\t\tcntl0, cntl1, enb, p7_trace_pci_msi ? 1 : 0);\n"
)
if old not in t:
    raise SystemExit("irq_handler_enter log anchor missing")
t = t.replace(old, new, 1)

old_pm = (
    "\tpr_info(\"PHASE7 ctx=acp fn=pm_resume_done resume=%u ret=%d irq=%d msi=%d stat0=0x%x stat1=0x%x cntl0=0x%x cntl1=0x%x enb=0x%x\\n\",\n"
)
new_pm = (
    "\tpr_info(\"PHASE7 ctx=acp fn=pm_resume_done resume=%u ret=%d irq=%d msi=%d t_mgr_ms=%lld stat0=0x%x stat1=0x%x cntl0=0x%x cntl1=0x%x enb=0x%x\\n\",\n"
)
if old_pm not in t:
    raise SystemExit("pm_resume_done anchor missing")
t = t.replace(old_pm, new_pm, 1)

old_pm2 = (
    "\t\tpci_dev_msi_enabled(pci) ? 1 : 0,\n"
    "\t\tstat0, stat1, cntl0, cntl1, enb);\n"
    "}\n\n\nstatic void handle_acp70"
)
# only first pm_resume_done call - add t_mgr_ms arg after msi
old_pm_args = (
    "\tpr_info(\"PHASE7 ctx=acp fn=pm_resume_done resume=%u ret=%d irq=%d msi=%d t_mgr_ms=%lld stat0=0x%x stat1=0x%x cntl0=0x%x cntl1=0x%x enb=0x%x\\n\",\n"
    "\t\tsnd_repair_phase7_acp_resume_id(), ret, pci->irq,\n"
    "\t\tpci_dev_msi_enabled(pci) ? 1 : 0,\n"
    "\t\tstat0, stat1, cntl0, cntl1, enb);\n"
)
new_pm_args = (
    "\tpr_info(\"PHASE7 ctx=acp fn=pm_resume_done resume=%u ret=%d irq=%d msi=%d t_mgr_ms=%lld stat0=0x%x stat1=0x%x cntl0=0x%x cntl1=0x%x enb=0x%x\\n\",\n"
    "\t\tsnd_repair_phase7_acp_resume_id(), ret, pci->irq,\n"
    "\t\tpci_dev_msi_enabled(pci) ? 1 : 0,\n"
    "\t\t(long long)snd_repair_phase7_t_mgr_reset_ms(1),\n"
    "\t\tstat0, stat1, cntl0, cntl1, enb);\n"
)
if old_pm_args not in t:
    raise SystemExit("pm_resume_done args anchor missing")
t = t.replace(old_pm_args, new_pm_args, 1)

ps.write_text(t)
print("correlate patches applied to tree")
PY

(
	cd "$SRC"
	{
		echo "From: snd-repair phase7 <snd-repair@local>"
		echo "Subject: [PATCH phase7] IRQ/STAT correlate (t_ms, cntl_write)"
		echo ""
		diff -u "$AMD.snd-repair-corr-base" "$AMD" | sed '1s|--- .*|--- a/drivers/soundwire/amd_manager.c|'
		diff -u "$PSC.snd-repair-corr-base" "$PSC" | sed '1s|--- .*|--- a/sound/soc/amd/ps/ps-common.c|'
		diff -u "$PS.snd-repair-corr-base" "$PS" | sed '1s|--- .*|--- a/sound/soc/amd/ps/pci-ps.c|'
	} >"$OUT"
)

rm -f "$AMD.snd-repair-corr-base" "$PS.snd-repair-corr-base" "$PSC.snd-repair-corr-base"
chmod +x "$SCRIPT_DIR/phase7-irq-snapshot.sh"
echo "Wrote $OUT"
