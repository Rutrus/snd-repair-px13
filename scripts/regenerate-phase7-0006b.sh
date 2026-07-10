#!/usr/bin/env bash
# Regenerate research/phase-7/proposed/0006b-stat-decode.patch from phase6 0007 base.
# Includes 0006b.1: second intr_decode snapshot after phase7_delay_ms (observation only).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

SRC="$KERNEL_SRC"
REPO="$REPO_ROOT"
OUT="$REPO/research/phase-7/proposed/0006b-stat-decode.patch"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cd "$SRC"
if ! rg -q 'fn=device_state_D0' drivers/soundwire/amd_manager.c 2>/dev/null; then
	echo "Phase 6 0007 base missing — run build-phase6-amd-trace.sh first" >&2
	exit 1
fi

cp drivers/soundwire/amd_manager.c "$TMP/base.c"

python3 - "$SRC/drivers/soundwire/amd_manager.c" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
t = p.read_text()

if "#include <linux/delay.h>" not in t:
    t = t.replace(
        "#include <linux/ktime.h>\n",
        "#include <linux/ktime.h>\n#include <linux/delay.h>\n", 1)
if "#include <linux/moduleparam.h>" not in t:
    t = t.replace(
        "#include <linux/module.h>\n",
        "#include <linux/module.h>\n#include <linux/moduleparam.h>\n", 1)

phase7_block = '''
/* Phase 7 / 0006b: pci-ps acp63.h bit labels (decode only, not handler paths). */
#define SND_REPAIR_ACP_SDW0_STAT_BIT	AMD_SDW0_EXT_INTR_MASK	/* BIT(21) */
#define SND_REPAIR_ACP_SDW1_STAT_BIT	AMD_SDW1_EXT_INTR_MASK	/* BIT(2) on STAT1 */
#define SND_REPAIR_ACP_ERROR_IRQ_BIT	(1U << 29)
#define SND_REPAIR_ACP_PDM_DMA_BIT	(1U << 16)	/* BIT(PDM_DMA_STAT) */
#define SND_REPAIR_ACP70_SDW0_DMA_MASK	0x1f800000U
#define SND_REPAIR_ACP_CNTL_HOST_WAKE_SDW0	AMD_SDW0_HOST_WAKE_INTR_MASK	/* BIT(22) */
#define SND_REPAIR_INTR_DECODE_INSTANCES	2

/* Phase 7: ms before second decode snapshot (0 = post_D0 only). NOT a production fix. */
static unsigned int snd_repair_phase7_delay_ms;
module_param_named(phase7_delay_ms, snd_repair_phase7_delay_ms, uint, 0644);
MODULE_PARM_DESC(phase7_delay_ms,
		 "Phase7: msleep before second intr_decode snapshot (0=control)");

static ktime_t snd_repair_phase7_decode_anchor;
static bool snd_repair_phase7_decode_anchor_valid;

'''
if "SND_REPAIR_INTR_DECODE_INSTANCES" not in t:
    t = t.replace(
        "static atomic_t amd_phase6_resume_seq;\n#define AMD_PHASE6_MAX_LINKS 2",
        "static atomic_t amd_phase6_resume_seq;\n" + phase7_block + "#define AMD_PHASE6_MAX_LINKS 2", 1)
elif "snd_repair_phase7_delay_ms" not in t:
    t = t.replace(
        "#define SND_REPAIR_INTR_DECODE_INSTANCES\t2\n",
        "#define SND_REPAIR_INTR_DECODE_INSTANCES\t2\n\n"
        "/* Phase 7: ms before second decode snapshot (0 = post_D0 only). NOT a production fix. */\n"
        "static unsigned int snd_repair_phase7_delay_ms;\n"
        "module_param_named(phase7_delay_ms, snd_repair_phase7_delay_ms, uint, 0644);\n"
        "MODULE_PARM_DESC(phase7_delay_ms,\n"
        "\t\t \"Phase7: msleep before second intr_decode snapshot (0=control)\");\n\n", 1)

fn = '''/* Phase 7 experiment 0006b — observation only. */
static void snd_repair_phase7_intr_decode(struct device *dev,
					  struct amd_sdw_manager *amd_manager,
					  struct sdw_bus *bus, const char *when)
{
	void __iomem *acp = amd_manager->acp_mmio;
	unsigned int inst = amd_manager->instance;
	unsigned int link = bus->link_id;
	u32 manager_mask = sdw_manager_reg_mask_array[inst];
	u32 cntl[SND_REPAIR_INTR_DECODE_INSTANCES];
	u32 stat[SND_REPAIR_INTR_DECODE_INSTANCES];
	u32 cntl_i, stat_i, stat_and_mask;
	unsigned int i;
	ktime_t now = ktime_get();
	s64 t_since_post_d0_ms = 0;
	s64 t_since_manager_reset_ms;

	if (!acp)
		return;

	if (!strcmp(when, "post_D0")) {
		snd_repair_phase7_decode_anchor = now;
		snd_repair_phase7_decode_anchor_valid = true;
	} else if (snd_repair_phase7_decode_anchor_valid) {
		t_since_post_d0_ms = ktime_to_ms(ktime_sub(now, snd_repair_phase7_decode_anchor));
	}

	t_since_manager_reset_ms = amd_phase6_since_reset_ms(amd_manager);

	for (i = 0; i < SND_REPAIR_INTR_DECODE_INSTANCES; i++) {
		cntl[i] = readl(acp + ACP_EXTERNAL_INTR_CNTL(i));
		stat[i] = readl(acp + ACP_EXTERNAL_INTR_STAT(i));
	}
	cntl_i = cntl[inst];
	stat_i = stat[inst];
	stat_and_mask = stat_i & manager_mask;

	dev_info(dev,
		 "PHASE7 ctx=amd fn=intr_decode when=%s link=%d resume=%d manager=%u t_since_post_D0_ms=%lld t_since_manager_reset_ms=%lld manager_mask=0x%x STAT0=0x%x STAT1=0x%x STATi=0x%x STAT&mask=0x%x CNTL0=0x%x CNTL1=0x%x\\n",
		 when, link, amd_phase6_resume_id(amd_manager), inst,
		 t_since_post_d0_ms, t_since_manager_reset_ms,
		 manager_mask, stat[0], stat[1], stat_i, stat_and_mask, cntl[0], cntl[1]);
	dev_info(dev,
		 "  manager_mask=0x%x INTR_CNTL(%u)=0x%x STAT(%u)=0x%x STAT&mask=0x%x\\n",
		 manager_mask, inst, cntl_i, inst, stat_i, stat_and_mask);
	dev_info(dev,
		 "  STAT0=0x%x STAT1=0x%x CNTL0=0x%x CNTL1=0x%x\\n",
		 stat[0], stat[1], cntl[0], cntl[1]);
	dev_info(dev,
		 "  decoded: SDW0=%u SDW1=%u DMA=%u ERROR=%u\\n",
		 !!(stat_i & SND_REPAIR_ACP_SDW0_STAT_BIT),
		 !!(stat_i & SND_REPAIR_ACP_SDW1_STAT_BIT),
		 !!(stat_i & SND_REPAIR_ACP70_SDW0_DMA_MASK),
		 !!(stat_i & SND_REPAIR_ACP_ERROR_IRQ_BIT));
	dev_info(dev,
		 "  decoded_stat0: sdw0=%u sdw1_bit2=%u error=%u pdm=%u dma_any=%u\\n",
		 !!(stat[0] & SND_REPAIR_ACP_SDW0_STAT_BIT),
		 !!(stat[0] & SND_REPAIR_ACP_SDW1_STAT_BIT),
		 !!(stat[0] & SND_REPAIR_ACP_ERROR_IRQ_BIT),
		 !!(stat[0] & SND_REPAIR_ACP_PDM_DMA_BIT),
		 !!(stat[0] & SND_REPAIR_ACP70_SDW0_DMA_MASK));
	dev_info(dev, "  decoded_stat1: sdw1=%u\\n",
		 !!(stat[1] & SND_REPAIR_ACP_SDW1_STAT_BIT));
	dev_info(dev,
		 "  decoded_cntl%u: sdw0_en=%u bit2=%u host_wake_sdw0=%u\\n",
		 inst, !!(cntl_i & SND_REPAIR_ACP_SDW0_STAT_BIT),
		 !!(cntl_i & SND_REPAIR_ACP_SDW1_STAT_BIT),
		 !!(cntl_i & SND_REPAIR_ACP_CNTL_HOST_WAKE_SDW0));
}

'''
if 'static void snd_repair_phase7_intr_decode' not in t:
    t = t.replace(
        "\treturn 0;\n}\n\nstatic int __maybe_unused amd_resume_runtime(struct device *dev)",
        "\treturn 0;\n}\n\n" + fn + "static int __maybe_unused amd_resume_runtime(struct device *dev)", 1)
elif "host_wake_sdw0" not in t and "decoded_cntl" in t:
    t = t.replace(
        "  decoded_cntl%u: sdw0_en=%u bit2=%u bit22=%u\\n",
        "  decoded_cntl%u: sdw0_en=%u bit2=%u host_wake_sdw0=%u\\n", 1)
    t = t.replace(
        "!!(cntl_i & SND_REPAIR_ACP_CNTL_BIT22));",
        "!!(cntl_i & SND_REPAIR_ACP_CNTL_HOST_WAKE_SDW0));", 1)
    t = t.replace(
        "#define SND_REPAIR_ACP_CNTL_BIT22\t(1U << 22)\n",
        "#define SND_REPAIR_ACP_CNTL_HOST_WAKE_SDW0\tAMD_SDW0_HOST_WAKE_INTR_MASK\t/* BIT(22) */\n", 1)

call = (
    "\t\tdev_info(dev,\n"
    "\t\t\t \"PHASE6 ctx=amd fn=intr_stat_post_D0 link=%d resume=%d stat=0x%x\\n\",\n"
    "\t\t\t bus->link_id, amd_phase6_resume_id(amd_manager),\n"
    "\t\t\t readl(amd_manager->acp_mmio +\n"
    "\t\t\t       ACP_EXTERNAL_INTR_STAT(amd_manager->instance)));\n"
    "\t\tif (ret)")

ins = (
    "\t\tdev_info(dev,\n"
    "\t\t\t \"PHASE6 ctx=amd fn=intr_stat_post_D0 link=%d resume=%d stat=0x%x\\n\",\n"
    "\t\t\t bus->link_id, amd_phase6_resume_id(amd_manager),\n"
    "\t\t\t readl(amd_manager->acp_mmio +\n"
    "\t\t\t       ACP_EXTERNAL_INTR_STAT(amd_manager->instance)));\n"
    "\t\tsnd_repair_phase7_intr_decode(dev, amd_manager, bus, \"post_D0\");\n"
    "\t\tif (snd_repair_phase7_delay_ms) {\n"
    "\t\t\tdev_info(dev,\n"
    "\t\t\t     \"PHASE7 ctx=amd fn=delay_before_decode link=%d resume=%d delay_ms=%u\\n\",\n"
    "\t\t\t     bus->link_id, amd_phase6_resume_id(amd_manager),\n"
    "\t\t\t     snd_repair_phase7_delay_ms);\n"
    "\t\t\tmsleep(snd_repair_phase7_delay_ms);\n"
    "\t\t\tsnd_repair_phase7_intr_decode(dev, amd_manager, bus, \"post_delay\");\n"
    "\t\t}\n"
    "\t\tif (ret)")

# Upgrade 0006b → 0006b.1 call site
old_ins = (
    "\t\tdev_info(dev,\n"
    "\t\t\t \"PHASE6 ctx=amd fn=intr_stat_post_D0 link=%d resume=%d stat=0x%x\\n\",\n"
    "\t\t\t bus->link_id, amd_phase6_resume_id(amd_manager),\n"
    "\t\t\t readl(amd_manager->acp_mmio +\n"
    "\t\t\t       ACP_EXTERNAL_INTR_STAT(amd_manager->instance)));\n"
    "\t\tsnd_repair_phase7_intr_decode(dev, amd_manager, bus, \"post_D0\");\n"
    "\t\tif (ret)")

if 'snd_repair_phase7_intr_decode(dev, amd_manager, bus, "post_delay")' not in t:
    if old_ins in t:
        t = t.replace(old_ins, ins, 1)
    elif call in t:
        t = t.replace(call, ins, 1)
    else:
        raise SystemExit("0006b call anchor missing")

p.write_text(t)
PY

diff -u "$TMP/base.c" "$SRC/drivers/soundwire/amd_manager.c" >"$TMP/0006b.diff" || true
{
	cat <<'EOF'
From: snd-repair phase7 <snd-repair@local>
Date: Fri, 10 Jul 2026 22:00:00 +0200
Subject: [PATCH phase7 0006b] soundwire: amd: INTR decode + delayed snapshot

Applies on Phase 6 trace series (0003–0007). Observation only (0006b + 0006b.1).

Regenerated by scripts/regenerate-phase7-0006b.sh (diff -u).

Signed-off-by: snd-repair phase7 <snd-repair@local>
---
EOF
	sed -e '1s|--- .*|--- a/drivers/soundwire/amd_manager.c|' \
	    -e '2s|+++ .*|+++ b/drivers/soundwire/amd_manager.c|' "$TMP/0006b.diff"
} >"$OUT"

cp "$TMP/base.c" "$SRC/drivers/soundwire/amd_manager.c"
patch -p1 --dry-run --forward <"$OUT" >/dev/null
echo "Wrote $OUT (dry-run OK)"
