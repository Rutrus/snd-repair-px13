#!/usr/bin/env python3
"""Apply W7 post-S2 timestamp trace on tas2783-sdw.c (requires W2+W4+W6)."""
from __future__ import annotations

import sys
from pathlib import Path


def must_replace(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f"ERROR: anchor missing for {label}")
    return text.replace(old, new, 1)


def main() -> int:
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <tas2783-sdw.c>", file=sys.stderr)
        return 2

    path = Path(sys.argv[1])
    text = path.read_text()

    if "W6 ctx=deferred fn=fw_reinit" not in text:
        print("ERROR: W6 not present — apply W6 first", file=sys.stderr)
        return 1
    if "W7 ctx=ts" in text:
        print("W7 already present")
        return 0

    if "#include <linux/ktime.h>" not in text:
        text = must_replace(
            text,
            "#include <linux/workqueue.h>\n",
            "#include <linux/workqueue.h>\n#include <linux/ktime.h>\n",
            "ktime include",
        )

    text = must_replace(
        text,
        'MODULE_PARM_DESC(deferred_reinit_on_port_prep,\n'
        '\t\t "W6 experiment: 2nd fw_reinit on first port PRE_PREP after W2");\n',
        'MODULE_PARM_DESC(deferred_reinit_on_port_prep,\n'
        '\t\t "W6 experiment: 2nd fw_reinit on first port PRE_PREP after W2");\n\n'
        'static bool w7_ts_trace = true;\n'
        'module_param(w7_ts_trace, bool, 0644);\n'
        'MODULE_PARM_DESC(w7_ts_trace,\n'
        '\t\t "W7: ms-since-S2-resume timestamps for W2/W5/W6/playback milestones");\n',
        "W7 module param",
    )

    text = must_replace(
        text,
        "static s32 tas2783_w2_force_fw_reinit(struct device *dev, struct sdw_slave *slave,\n"
        "\t\t\t\t\t      const char *when);\n",
        "static s32 tas2783_w2_force_fw_reinit(struct device *dev, struct sdw_slave *slave,\n"
        "\t\t\t\t\t      const char *when);\n"
        "static void tas2783_w7_s2_reset(void);\n"
        "static void tas2783_w7_s2_anchor(struct device *dev, u8 uid);\n"
        "static void tas2783_w7_ts(struct device *dev, u8 uid, const char *event);\n"
        "static void tas2783_w7_ts_once_hw_params(struct device *dev, u8 uid);\n"
        "static void tas2783_w7_ts_once_port_prep(struct device *dev, u8 uid);\n",
        "W7 forward declarations",
    )

    w7_helpers = r'''
static u64 w7_s2_anchor_ns;
static bool w7_s2_anchor_valid;
static bool w7_logged_hw_params;
static bool w7_logged_port_prep;

static void tas2783_w7_ts(struct device *dev, u8 uid, const char *event);

static void tas2783_w7_s2_reset(void)
{
	w7_s2_anchor_valid = false;
	w7_logged_hw_params = false;
	w7_logged_port_prep = false;
}

static void tas2783_w7_s2_anchor(struct device *dev, u8 uid)
{
	if (w7_s2_anchor_valid)
		return;
	w7_s2_anchor_ns = ktime_get_boottime_ns();
	w7_s2_anchor_valid = true;
	tas2783_w7_ts(dev, uid, "s2_resume_anchor");
}

static void tas2783_w7_ts(struct device *dev, u8 uid, const char *event)
{
	u64 ms = 0;

	if (!w7_ts_trace || !dev)
		return;
	if (w7_s2_anchor_valid)
		ms = div_u64(ktime_get_boottime_ns() - w7_s2_anchor_ns, NSEC_PER_MSEC);
	dev_info(dev, "W7 ctx=ts uid=%d ms=%llu event=%s\n", uid, ms, event);
}

static void tas2783_w7_ts_once_hw_params(struct device *dev, u8 uid)
{
	if (w7_logged_hw_params)
		return;
	w7_logged_hw_params = true;
	tas2783_w7_ts(dev, uid, "first_hw_params");
}

static void tas2783_w7_ts_once_port_prep(struct device *dev, u8 uid)
{
	if (w7_logged_port_prep)
		return;
	w7_logged_port_prep = true;
	tas2783_w7_ts(dev, uid, "first_port_prep");
}

'''
    text = must_replace(
        text,
        "static void tas2783_w6_deferred_reinit_work(struct work_struct *work)\n",
        w7_helpers + "static void tas2783_w6_deferred_reinit_work(struct work_struct *work)\n",
        "W7 helpers",
    )

    text = must_replace(
        text,
        "\t\ttas2783_w6_cancel_second_reinit(tas_dev);\n"
        "\t}\n"
        "\tif (tas_dev) {\n"
        "\t\ttas_dev->post_system_sleep = true;\n",
        "\t\ttas2783_w6_cancel_second_reinit(tas_dev);\n"
        "\t\ttas2783_w7_s2_reset();\n"
        "\t}\n"
        "\tif (tas_dev) {\n"
        "\t\ttas_dev->post_system_sleep = true;\n",
        "W7 reset on suspend",
    )

    text = must_replace(
        text,
        "\tW4B_PHASE_SET(tas_dev, \"RESUME\");\n"
        "\ttas2783_w4_life(dev, uid, \"resume\", \"enter\");\n",
        "\tW4B_PHASE_SET(tas_dev, \"RESUME\");\n"
        "\ttas2783_w7_s2_anchor(dev, uid);\n"
        "\ttas2783_w4_life(dev, uid, \"resume\", \"enter\");\n",
        "W7 anchor on resume",
    )

    text = must_replace(
        text,
        "\tif (status == SDW_SLAVE_ATTACHED && tas_dev->post_system_sleep) {\n"
        "\t\tW4B_PHASE_SET(tas_dev, \"RESUME\");\n",
        "\tif (status == SDW_SLAVE_ATTACHED && tas_dev->post_system_sleep) {\n"
        "\t\tW4B_PHASE_SET(tas_dev, \"RESUME\");\n"
        "\t\ttas2783_w7_s2_anchor(dev, tas2783_w4_uid(tas_dev));\n",
        "W7 anchor on update_status",
    )

    text = must_replace(
        text,
        "\ttas2783_w4_life(dev, uid, when, \"force_fw_reinit\");\n"
        "\tdev_info(dev, \"W2 ctx=tas fn=force_fw_reinit when=%s uid=%d\\n\", when, uid);\n"
        "\ttas_dev->post_system_sleep = false;\n"
        "\tret = tas2783_fw_reinit(dev, slave);\n",
        "\ttas2783_w4_life(dev, uid, when, \"force_fw_reinit\");\n"
        "\tdev_info(dev, \"W2 ctx=tas fn=force_fw_reinit when=%s uid=%d\\n\", when, uid);\n"
        "\ttas_dev->post_system_sleep = false;\n"
        "\ttas2783_w7_ts(dev, uid, \"w2_fw_reinit_start\");\n"
        "\tret = tas2783_fw_reinit(dev, slave);\n"
        "\ttas2783_w7_ts(dev, uid, ret ? \"w2_fw_reinit_end_err\" : \"w2_fw_reinit_end\");\n",
        "W7 W2 timestamps",
    )

    text = must_replace(
        text,
        "\tW4B_PHASE_SET(tas_dev, \"W6_DEFERRED\");\n"
        "\tdev_info(dev, \"W6 ctx=deferred fn=fw_reinit uid=%d delay_ms=%u\\n\",\n",
        "\tW4B_PHASE_SET(tas_dev, \"W6_DEFERRED\");\n"
        "\ttas2783_w7_ts(dev, tas2783_w4_uid(tas_dev), \"w6_fw_reinit_start\");\n"
        "\tdev_info(dev, \"W6 ctx=deferred fn=fw_reinit uid=%d delay_ms=%u\\n\",\n",
        "W7 W6 start",
    )

    text = must_replace(
        text,
        "\tret = tas2783_fw_reinit(dev, slave);\n"
        "\tdev_info(dev, \"W6 ctx=deferred fn=fw_reinit uid=%d ret=%d\\n\",\n"
        "\t\t tas2783_w4_uid(tas_dev), ret);\n"
        "\ttas_dev->w6_second_reinit_pending = false;\n"
        "}\n\n"
        "static void tas2783_w6_cancel_second_reinit",
        "\tret = tas2783_fw_reinit(dev, slave);\n"
        "\tdev_info(dev, \"W6 ctx=deferred fn=fw_reinit uid=%d ret=%d\\n\",\n"
        "\t\t tas2783_w4_uid(tas_dev), ret);\n"
        "\ttas2783_w7_ts(dev, tas2783_w4_uid(tas_dev),\n"
        "\t\t      ret ? \"w6_fw_reinit_end_err\" : \"w6_fw_reinit_end\");\n"
        "\ttas_dev->w6_second_reinit_pending = false;\n"
        "}\n\n"
        "static void tas2783_w6_cancel_second_reinit",
        "W7 W6 end",
    )

    text = must_replace(
        text,
        "\tW4B_PHASE_SET(tas_dev, \"RUNTIME\");\n"
        "\ttas2783_w4_life(tas_dev->dev, uid, \"hw_params\", \"enter\");\n",
        "\tW4B_PHASE_SET(tas_dev, \"RUNTIME\");\n"
        "\ttas2783_w7_ts_once_hw_params(tas_dev->dev, uid);\n"
        "\ttas2783_w4_life(tas_dev->dev, uid, \"hw_params\", \"enter\");\n",
        "W7 first hw_params",
    )

    text = must_replace(
        text,
        "\tcase SDW_OPS_PORT_PRE_PREP:\n"
        "\t\ttas2783_w4_life(dev, uid, \"port_prep\", \"pre_prep\");\n"
        "\t\tW4B_PHASE_SET(tas_dev, \"RUNTIME\");\n",
        "\tcase SDW_OPS_PORT_PRE_PREP:\n"
        "\t\ttas2783_w7_ts_once_port_prep(dev, uid);\n"
        "\t\ttas2783_w4_life(dev, uid, \"port_prep\", \"pre_prep\");\n"
        "\t\tW4B_PHASE_SET(tas_dev, \"RUNTIME\");\n",
        "W7 first port_prep",
    )

    text = must_replace(
        text,
        "\tW4B_PHASE_SET(tas_dev, \"W5_MANUAL\");\n"
        "\tdev_info(tas_dev->dev, \"W5 ctx=manual fn=fw_reinit uid=%d trigger=1\\n\",\n"
        "\t\t tas2783_w4_uid(tas_dev));\n"
        "\tret = tas2783_fw_reinit(&slave->dev, slave);\n",
        "\tW4B_PHASE_SET(tas_dev, \"W5_MANUAL\");\n"
        "\tdev_info(tas_dev->dev, \"W5 ctx=manual fn=fw_reinit uid=%d trigger=1\\n\",\n"
        "\t\t tas2783_w4_uid(tas_dev));\n"
        "\ttas2783_w7_ts(tas_dev->dev, tas2783_w4_uid(tas_dev), \"w5_fw_reinit_start\");\n"
        "\tret = tas2783_fw_reinit(&slave->dev, slave);\n",
        "W7 W5 start",
    )

    text = must_replace(
        text,
        "\tdev_info(tas_dev->dev, \"W5 ctx=manual fn=fw_reinit uid=%d ret=%d\\n\",\n"
        "\t\t tas2783_w4_uid(tas_dev), ret);\n"
        "\treturn count;\n",
        "\tdev_info(tas_dev->dev, \"W5 ctx=manual fn=fw_reinit uid=%d ret=%d\\n\",\n"
        "\t\t tas2783_w4_uid(tas_dev), ret);\n"
        "\ttas2783_w7_ts(tas_dev->dev, tas2783_w4_uid(tas_dev),\n"
        "\t\t      ret ? \"w5_fw_reinit_end_err\" : \"w5_fw_reinit_end\");\n"
        "\treturn count;\n",
        "W7 W5 end",
    )

    path.write_text(text)
    print(f"W7 applied to {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
