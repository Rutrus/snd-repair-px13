#!/usr/bin/env bash
# Regenerate research/q2-fw-resume/patches/0001 from live kernel tree (upstream A+B+C).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

SRC="$KERNEL_SRC"
C="$SRC/sound/soc/codecs/tas2783-sdw.c"
PATCH="$REPO_ROOT/research/q2-fw-resume/patches/0001-tas2783-q2-resume-trace.patch"

[[ -f "$C" ]] || { echo "Missing $C — run apply-upstream-patches.sh first" >&2; exit 1; }
rg -q tas2783_fw_reinit "$C" || {
	echo "Series B (0003) not on tree — run apply-upstream-patches.sh first" >&2
	exit 1
}
rg -q TAS2783Q2 "$C" && {
	echo "Q2 trace already in tree — reset kernel tree or reverse patch first" >&2
	exit 1
}

TMP="$(mktemp -d)"
cp "$C" "$TMP/before.c"
cp "$C" "$TMP/after.c"

python3 - "$TMP/after.c" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()

def ins(after: str, block: str) -> None:
    global text
    if after not in text:
        raise SystemExit(f"anchor not found: {after!r}")
    text = text.replace(after, after + block, 1)

def ins_before(before: str, block: str) -> None:
    global text
    if before not in text:
        raise SystemExit(f"anchor not found: {before!r}")
    text = text.replace(before, block + before, 1)

# --- tas2783_fw_ready ---
ins(
    "\tconst u8 *buf = NULL;\n",
    "\tu8 uid = tas_dev->sdw_peripheral ?\n"
    "\t\t tas_dev->sdw_peripheral->id.unique_id : 0;\n\n"
    "\tdev_info(tas_dev->dev, \"TAS2783Q2 fn=fw_ready enter uid=0x%x fmw=%p\\n\",\n"
    "\t\t uid, fmw);\n",
)

ins(
    "\t\tif (ret < 0) {\n"
    "\t\t\tdev_err(tas_dev->dev,\n"
    "\t\t\t\t\"FW download failed: %d\", ret);\n",
    "\t\t\tdev_info(tas_dev->dev,\n"
    "\t\t\t\t \"TAS2783Q2 fn=fw_ready nwrite_fail uid=0x%x file_idx=%d rc=%d\\n\",\n"
    "\t\t\t\t uid, cur_file, ret);\n",
)

ins(
    "\ttas_dev->fw_dl_task_done = true;\n",
    "\tdev_info(tas_dev->dev,\n"
    "\t\t \"TAS2783Q2 fn=fw_ready exit uid=0x%x ret=%d cur_file=%d fmw_ok=%d success=%d done=%d\\n\",\n"
    "\t\t uid, ret, cur_file, fmw && fmw->data ? 1 : 0,\n"
    "\t\t tas_dev->fw_dl_success, tas_dev->fw_dl_task_done);\n",
)

# --- tas_sdw_hw_params ---
ins(
    "\tif (!tas_dev->fw_dl_success && !tas_dev->fw_dl_task_done &&\n"
    "\t    tas_dev->status == SDW_SLAVE_ATTACHED) {\n",
    "\t\tdev_info(tas_dev->dev,\n"
    "\t\t\t \"TAS2783Q2 fn=hw_params reinit uid=0x%x hw_init=%d\\n\",\n"
    "\t\t\t sdw_peripheral->id.unique_id, tas_dev->hw_init);\n",
)

ins(
    "\tif (!tas_dev->fw_dl_success && !tas_dev->fw_dl_task_done) {\n",
    "\t\tdev_info(tas_dev->dev,\n"
    "\t\t\t \"TAS2783Q2 fn=hw_params wait uid=0x%x success=%d done=%d\\n\",\n"
    "\t\t\t sdw_peripheral->id.unique_id,\n"
    "\t\t\t tas_dev->fw_dl_success, tas_dev->fw_dl_task_done);\n",
)

ins(
    "\t\tif (!ret)\n"
    "\t\t\tdev_err(tas_dev->dev, \"fw download wait timeout in hw_params\");\n",
    "\t\tdev_info(tas_dev->dev,\n"
    "\t\t\t \"TAS2783Q2 fn=hw_params wait_done uid=0x%x waited=%d success=%d done=%d\\n\",\n"
    "\t\t\t sdw_peripheral->id.unique_id, ret,\n"
    "\t\t\t tas_dev->fw_dl_success, tas_dev->fw_dl_task_done);\n",
)

# --- system_suspend ---
ins(
    "\t\ttas_dev->fw_dl_success = false;\n",
    "\t\tdev_info(dev,\n"
    "\t\t\t \"TAS2783Q2 fn=system_suspend invalidate uid=0x%x\\n\",\n"
    "\t\t\t tas_dev->sdw_peripheral ?\n"
    "\t\t\t tas_dev->sdw_peripheral->id.unique_id : 0);\n",
)

# --- system_resume ---
old_resume = (
    "\tif (tas_dev->status == SDW_SLAVE_ATTACHED && !tas_dev->hw_init)\n"
    "\t\tret = tas2783_fw_reinit(dev, slave);\n"
    "\treturn ret;\n"
)
new_resume = (
    "\tif (tas_dev->status == SDW_SLAVE_ATTACHED && !tas_dev->hw_init) {\n"
    "\t\tdev_info(dev,\n"
    "\t\t\t \"TAS2783Q2 fn=system_resume reinit uid=0x%x status=%d hw_init=%d success=%d done=%d\\n\",\n"
    "\t\t\t slave->id.unique_id, tas_dev->status, tas_dev->hw_init,\n"
    "\t\t\t tas_dev->fw_dl_success, tas_dev->fw_dl_task_done);\n"
    "\t\tret = tas2783_fw_reinit(dev, slave);\n"
    "\t} else {\n"
    "\t\tdev_info(dev,\n"
    "\t\t\t \"TAS2783Q2 fn=system_resume skip_reinit uid=0x%x status=%d hw_init=%d success=%d done=%d\\n\",\n"
    "\t\t\t slave->id.unique_id, tas_dev->status, tas_dev->hw_init,\n"
    "\t\t\t tas_dev->fw_dl_success, tas_dev->fw_dl_task_done);\n"
    "\t}\n"
    "\treturn ret;\n"
)
if old_resume not in text:
    raise SystemExit("system_resume anchor not found")
text = text.replace(old_resume, new_resume, 1)

# --- tas_io_init ---
ins(
    "\tu8 unique_id = tas_dev->sdw_peripheral->id.unique_id;\n\n",
    "\tdev_info(dev,\n"
    "\t\t \"TAS2783Q2 fn=io_init enter uid=0x%x hw_init=%d success=%d done=%d\\n\",\n"
    "\t\t unique_id, tas_dev->hw_init, tas_dev->fw_dl_success,\n"
    "\t\t tas_dev->fw_dl_task_done);\n\n",
)

ins_before(
    "\tret = wait_event_timeout(tas_dev->fw_wait, tas_dev->fw_dl_task_done,\n"
    "\t\t\t\t msecs_to_jiffies(TIMEOUT_FW_DL_MS));\n"
    "\tif (!ret) {\n",
    "\tdev_info(dev, \"TAS2783Q2 fn=io_init nowait uid=0x%x ret=%d bin=%s\\n\",\n"
    "\t\t unique_id, ret, tas_dev->rca_binaryname);\n\n",
)

ins(
    "\t\tret = -EAGAIN;\n"
    "\t} else {\n",
    "\t\tdev_info(dev,\n"
    "\t\t\t \"TAS2783Q2 fn=io_init wait uid=0x%x waited=%d success=%d done=%d\\n\",\n"
    "\t\t\t unique_id, ret, tas_dev->fw_dl_success, tas_dev->fw_dl_task_done);\n",
)

ins_before(
    "\treturn ret;\n"
    "}\n\n"
    "static s32 tas2783_fw_reinit(struct device *dev, struct sdw_slave *slave)\n",
    "\tdev_info(dev,\n"
    "\t\t \"TAS2783Q2 fn=io_init exit uid=0x%x ret=%d hw_init=%d success=%d done=%d\\n\",\n"
    "\t\t unique_id, ret, tas_dev->hw_init, tas_dev->fw_dl_success, tas_dev->fw_dl_task_done);\n",
)

# --- tas2783_fw_reinit ---
ins(
    "static s32 tas2783_fw_reinit(struct device *dev, struct sdw_slave *slave)\n"
    "{\n"
    "\tstruct tas2783_prv *tas_dev = dev_get_drvdata(dev);\n\n",
    "\tdev_info(dev, \"TAS2783Q2 fn=fw_reinit enter uid=0x%x\\n\",\n"
    "\t\t slave->id.unique_id);\n\n",
)

# --- tas_update_status ---
ins(
    "\tstruct device *dev = &slave->dev;\n\n",
    "\tdev_info(dev,\n"
    "\t\t \"TAS2783Q2 fn=update_status uid=0x%x status=%d hw_init=%d success=%d done=%d\\n\",\n"
    "\t\t slave->id.unique_id, status, tas_dev->hw_init,\n"
    "\t\t tas_dev->fw_dl_success, tas_dev->fw_dl_task_done);\n\n",
)

old_skip = (
    "\tif (tas_dev->hw_init || tas_dev->status != SDW_SLAVE_ATTACHED)\n"
    "\t\treturn 0;\n"
)
new_skip = (
    "\tif (tas_dev->hw_init || tas_dev->status != SDW_SLAVE_ATTACHED) {\n"
    "\t\tdev_info(dev,\n"
    "\t\t\t \"TAS2783Q2 fn=update_status skip_io_init uid=0x%x hw_init=%d status=%d\\n\",\n"
    "\t\t\t slave->id.unique_id, tas_dev->hw_init, tas_dev->status);\n"
    "\t\treturn 0;\n"
    "\t}\n"
)
if old_skip not in text:
    raise SystemExit("update_status skip anchor not found")
text = text.replace(old_skip, new_skip, 1)

ins_before(
    "\treturn tas_io_init(&slave->dev, slave);\n",
    "\tdev_info(dev, \"TAS2783Q2 fn=update_status call_io_init uid=0x%x\\n\",\n"
    "\t\t slave->id.unique_id);\n",
)

open(path, "w").write(text)
print("OK: Q2 trace injected into", path)
PY

diff -u "$TMP/before.c" "$TMP/after.c" >"$TMP/raw.diff" || true
{ head -n 12 "$PATCH" 2>/dev/null || cat <<'HDR'
From: snd_repair Q2 investigation <snd-repair@local>
Date: Sun, 12 Jul 2026 00:00:00 +0200
Subject: [PATCH q2] ASoC: tas2783: Q2 firmware resume trace (TAS2783Q2)

Observation-only probes for H1–H4 discrimination after Q1 closed.
Apply on top of upstream series B (0001–0003). Not for upstream submission.

grep: journalctl -k | grep TAS2783Q2

Signed-off-by: snd_repair Q2 investigation <snd-repair@local>
---
HDR
} | head -n 11 >"$PATCH"

# Wrap as git-style patch for sound/soc/codecs/tas2783-sdw.c
{
	echo "diff --git a/sound/soc/codecs/tas2783-sdw.c b/sound/soc/codecs/tas2783-sdw.c"
	echo "--- a/sound/soc/codecs/tas2783-sdw.c"
	echo "+++ b/sound/soc/codecs/tas2783-sdw.c"
	tail -n +3 "$TMP/raw.diff"
} >>"$PATCH"

ADDED=$(grep -c '^+' "$TMP/raw.diff" || true)
REMOVED=$(grep -c '^-' "$TMP/raw.diff" || true)
# shellcheck disable=SC2001
sed -i "s|^ sound/soc/codecs/tas2783-sdw.c | sound/soc/codecs/tas2783-sdw.c | 1 file changed, ${ADDED} insertions(+), ${REMOVED} deletions(-)|" "$PATCH" 2>/dev/null || true

rm -rf "$TMP"
echo "==> Wrote $PATCH"
echo "Test: cd $SRC && patch -p1 --dry-run < $PATCH"
