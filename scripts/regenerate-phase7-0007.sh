#!/usr/bin/env bash
# Regenerate research/phase-7/proposed/0007-irq-delivery-trace.patch (pci-ps.c only).
# Base: Phase 6 trace already applied (0003–0007); 0007 extends pci-ps observation.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

SRC="$KERNEL_SRC"
OUT="$REPO_ROOT/research/phase-7/proposed/0007-irq-delivery-trace.patch"
PCI="$SRC/sound/soc/amd/ps/pci-ps.c"

[[ -f "$PCI" ]] || { echo "Missing $PCI — run prepare-kernel-tree.sh" >&2; exit 1; }

cp "$PCI" "$PCI.snd-repair-p7-0007-base"

python3 <<'PY'
from pathlib import Path

p = Path("/home/rutrus/snd_repair/linux-source-7.0.0/sound/soc/amd/ps/pci-ps.c")
t = p.read_text()

header = """
/* Phase 7 / 0007: IRQ delivery trace (pci-ps) — observation only, no behaviour change. */
static unsigned int snd_repair_phase7_acp_resume_n;
static int p7_trace_pci_irq;
static bool p7_trace_pci_msi;

static u32 snd_repair_phase7_acp_resume_id(void)
{
\treturn snd_repair_phase7_acp_resume_n;
}

static void snd_repair_phase7_log_irq_regs(struct acp63_dev_data *adata,
\t\t\t\t\t   u32 *stat0, u32 *stat1,
\t\t\t\t\t   u32 *cntl0, u32 *cntl1, u32 *enb)
{
\t*stat0 = readl(adata->acp63_base + ACP_EXTERNAL_INTR_STAT);
\t*stat1 = readl(adata->acp63_base + ACP_EXTERNAL_INTR_STAT1);
\t*cntl0 = readl(adata->acp63_base + ACP_EXTERNAL_INTR_CNTL);
\t*cntl1 = readl(adata->acp63_base + ACP_EXTERNAL_INTR_CNTL1);
\t*enb = readl(adata->acp63_base + ACP_EXTERNAL_INTR_ENB);
}

static void snd_repair_phase7_pm_resume_trace(struct device *dev,
\t\t\t\t\t      struct acp63_dev_data *adata, int ret)
{
\tstruct pci_dev *pci = to_pci_dev(dev);
\tu32 stat0 = 0, stat1 = 0, cntl0 = 0, cntl1 = 0, enb = 0;

\tif (adata && adata->acp63_base)
\t\tsnd_repair_phase7_log_irq_regs(adata, &stat0, &stat1, &cntl0, &cntl1, &enb);
\tpr_info("PHASE7 ctx=acp fn=pm_resume_done resume=%u ret=%d irq=%d msi=%d stat0=0x%x stat1=0x%x cntl0=0x%x cntl1=0x%x enb=0x%x\\n",
\t\tsnd_repair_phase7_acp_resume_id(), ret, pci->irq,
\t\tpci_dev_msi_enabled(pci) ? 1 : 0,
\t\tstat0, stat1, cntl0, cntl1, enb);
}

"""

if "snd_repair_phase7_acp_resume_n" not in t:
    anchor = "#include \"acp63.h\"\n"
    if anchor not in t:
        raise SystemExit("include anchor missing")
    t = t.replace(anchor, anchor + header, 1)

# 0007.1 + 0007.4: handler enter/exit (replaces PHASE6 single-line enter)
old_enter = (
    "\text_intr_stat = readl(adata->acp63_base + ACP_EXTERNAL_INTR_STAT);\n"
    "\tpr_info(\"PHASE6 ctx=acp fn=irq_handler_enter stat=0x%x\\n\", ext_intr_stat);\n"
    "\tif (ext_intr_stat & ACP_SDW0_STAT) {\n"
)
new_enter = (
    "\t{\n"
    "\t\tu32 cntl0, cntl1, enb;\n"
    "\n"
    "\t\text_intr_stat = readl(adata->acp63_base + ACP_EXTERNAL_INTR_STAT);\n"
    "\t\text_intr_stat1 = readl(adata->acp63_base + ACP_EXTERNAL_INTR_STAT1);\n"
    "\t\tsnd_repair_phase7_log_irq_regs(adata, &ext_intr_stat, &ext_intr_stat1,\n"
    "\t\t\t\t\t\t       &cntl0, &cntl1, &enb);\n"
    "\t\tpr_info(\"PHASE7 ctx=acp fn=irq_handler_enter irq=%d resume=%u stat0=0x%x stat1=0x%x cntl0=0x%x cntl1=0x%x enb=0x%x msi=%d\\n\",\n"
    "\t\t\tirq, snd_repair_phase7_acp_resume_id(), ext_intr_stat, ext_intr_stat1,\n"
    "\t\t\tcntl0, cntl1, enb, p7_trace_pci_msi ? 1 : 0);\n"
    "\t}\n"
    "\tif (ext_intr_stat & ACP_SDW0_STAT) {\n"
)
if old_enter not in t:
    raise SystemExit("handler enter anchor missing (apply Phase 6 0005 first?)")
t = t.replace(old_enter, new_enter, 1)

# Remove duplicate ext_intr_stat1 read later
old_stat1 = "\n\text_intr_stat1 = readl(adata->acp63_base + ACP_EXTERNAL_INTR_STAT1);\n\tif (ext_intr_stat1 & ACP_SDW1_STAT) {"
new_stat1 = "\n\tif (ext_intr_stat1 & ACP_SDW1_STAT) {"
if old_stat1 not in t:
    raise SystemExit("stat1 re-read anchor missing")
t = t.replace(old_stat1, new_stat1, 1)

# SDW1 ack trace (0007.4)
old_sdw1 = (
    "\tif (ext_intr_stat1 & ACP_SDW1_STAT) {\n"
    "\t\twritel(ACP_SDW1_STAT, adata->acp63_base + ACP_EXTERNAL_INTR_STAT1);\n"
)
new_sdw1 = (
    "\tif (ext_intr_stat1 & ACP_SDW1_STAT) {\n"
    "\t\tpr_info(\"PHASE7 ctx=acp fn=sdw1_irq resume=%u stat1=0x%x ack=0x%x\\n\",\n"
    "\t\t\tsnd_repair_phase7_acp_resume_id(), ext_intr_stat1, ACP_SDW1_STAT);\n"
    "\t\twritel(ACP_SDW1_STAT, adata->acp63_base + ACP_EXTERNAL_INTR_STAT1);\n"
)
if old_sdw1 not in t:
    raise SystemExit("sdw1 anchor missing")
t = t.replace(old_sdw1, new_sdw1, 1)

# handler exit (0007.4)
old_exit = (
    "\tif (irq_flag | wake_irq_flag)\n"
    "\t\treturn IRQ_HANDLED;\n"
    "\telse\n"
    "\t\treturn IRQ_NONE;\n"
    "}"
)
new_exit = (
    "\tif (irq_flag | wake_irq_flag) {\n"
    "\t\tpr_info(\"PHASE7 ctx=acp fn=irq_handler_exit resume=%u ret=HANDLED sdw0=%d sdw1=%d wake=%d dma=%d\\n\",\n"
    "\t\t\tsnd_repair_phase7_acp_resume_id(), !!(ext_intr_stat & ACP_SDW0_STAT),\n"
    "\t\t\t!!(ext_intr_stat1 & ACP_SDW1_STAT), wake_irq_flag, sdw_dma_irq_flag);\n"
    "\t\treturn IRQ_HANDLED;\n"
    "\t}\n"
    "\tpr_info(\"PHASE7 ctx=acp fn=irq_handler_exit resume=%u ret=NONE sdw0=%d sdw1=%d wake=%d dma=%d\\n\",\n"
    "\t\tsnd_repair_phase7_acp_resume_id(), !!(ext_intr_stat & ACP_SDW0_STAT),\n"
    "\t\t!!(ext_intr_stat1 & ACP_SDW1_STAT), wake_irq_flag, sdw_dma_irq_flag);\n"
    "\treturn IRQ_NONE;\n"
    "}"
)
if old_exit not in t:
    raise SystemExit("handler exit anchor missing")
t = t.replace(old_exit, new_exit, 1)

# 0007.2: request_irq
old_req = (
    "\tif (ret) {\n"
    "\t\tdev_err(&pci->dev, \"ACP PCI IRQ request failed\\n\");\n"
    "\t\tgoto de_init;\n"
    "\t}\n"
    "\tret = get_acp63_device_config(pci, adata);\n"
)
new_req = (
    "\tif (ret) {\n"
    "\t\tdev_err(&pci->dev, \"ACP PCI IRQ request failed\\n\");\n"
    "\t\tgoto de_init;\n"
    "\t}\n"
    "\tp7_trace_pci_irq = pci->irq;\n"
    "\tp7_trace_pci_msi = pci_dev_msi_enabled(pci);\n"
    "\tpr_info(\"PHASE7 ctx=acp fn=request_irq irq=%d flags=0x%x msi=%d resume=%u\\n\",\n"
    "\t\tpci->irq, irqflags, p7_trace_pci_msi ? 1 : 0,\n"
    "\t\tsnd_repair_phase7_acp_resume_id());\n"
    "\tret = get_acp63_device_config(pci, adata);\n"
)
if old_req not in t:
    raise SystemExit("request_irq anchor missing")
t = t.replace(old_req, new_req, 1)

# 0007.3 + resume counter: system resume wrapper
old_resume = (
    "static int snd_acp_resume(struct device *dev)\n"
    "{\n"
    "\treturn acp_hw_resume(dev);\n"
    "}"
)
new_resume = (
    "static int snd_acp_resume(struct device *dev)\n"
    "{\n"
    "\tstruct acp63_dev_data *adata = dev_get_drvdata(dev);\n"
    "\tstruct pci_dev *pci = to_pci_dev(dev);\n"
    "\tint ret;\n"
    "\n"
    "\tsnd_repair_phase7_acp_resume_n++;\n"
    "\tpr_info(\"PHASE7 ctx=acp fn=pm_resume_enter resume=%u irq=%d msi=%d\\n\",\n"
    "\t\tsnd_repair_phase7_acp_resume_id(), pci->irq,\n"
    "\t\tpci_dev_msi_enabled(pci) ? 1 : 0);\n"
    "\tret = acp_hw_resume(dev);\n"
    "\tsnd_repair_phase7_pm_resume_trace(dev, adata, ret);\n"
    "\treturn ret;\n"
    "}"
)
if old_resume not in t:
    raise SystemExit("snd_acp_resume anchor missing")
t = t.replace(old_resume, new_resume, 1)

p.write_text(t)
print("patched pci-ps.c")
PY

(
	cd "$SRC"
	diff -u "$PCI.snd-repair-p7-0007-base" "$PCI" >"$OUT.raw" || true
)

{
	cat <<EOF
From: snd-repair phase7 <snd-repair@local>
Date: Sat, 11 Jul 2026 02:00:00 +0200
Subject: [PATCH phase7] IRQ delivery trace (0007.1–0007.4, pci-ps)

Observation only — trace acp63_irq_handler, request_irq, and system resume
(MSI/STAT/CNTL). Applies on Phase 6 trace base (0003–0007).

Signed-off-by: snd-repair phase7 <snd-repair@local>
---
EOF
	sed -e '1s|--- .*|--- a/sound/soc/amd/ps/pci-ps.c|' \
	    -e '2s|+++ .*|+++ b/sound/soc/amd/ps/pci-ps.c|' "$OUT.raw"
} >"$OUT"

rm -f "$PCI.snd-repair-p7-0007-base" "$OUT.raw"
echo "Wrote $OUT"
