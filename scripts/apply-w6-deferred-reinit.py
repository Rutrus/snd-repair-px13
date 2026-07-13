#!/usr/bin/env python3
"""Apply W6 deferred second fw_reinit experiment on tas2783-sdw.c (requires W2+W4)."""
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

    if "W2 ctx=tas fn=force_fw_reinit" not in text:
        print("ERROR: W2 not present — apply W2 first", file=sys.stderr)
        return 1
    if "W6 ctx=deferred fn=fw_reinit" in text:
        print("W6 already present")
        return 0

    if "#include <linux/workqueue.h>" not in text:
        text = must_replace(
            text,
            "#include <linux/wait.h>\n",
            "#include <linux/wait.h>\n#include <linux/workqueue.h>\n",
            "workqueue include",
        )

    text = must_replace(
        text,
        'MODULE_PARM_DESC(w4b_write_trace,\n'
        '\t\t "W4b: log every chip write with phase+fn (PASS vs FAIL write diff)");\n',
        'MODULE_PARM_DESC(w4b_write_trace,\n'
        '\t\t "W4b: log every chip write with phase+fn (PASS vs FAIL write diff)");\n\n'
        'static unsigned int deferred_reinit_ms;\n'
        'module_param(deferred_reinit_ms, uint, 0644);\n'
        'MODULE_PARM_DESC(deferred_reinit_ms,\n'
        '\t\t "W6 experiment: schedule 2nd fw_reinit N ms after W2 (0=disabled)");\n\n'
        'static bool deferred_reinit_on_port_prep;\n'
        'module_param(deferred_reinit_on_port_prep, bool, 0644);\n'
        'MODULE_PARM_DESC(deferred_reinit_on_port_prep,\n'
        '\t\t "W6 experiment: 2nd fw_reinit on first port PRE_PREP after W2");\n',
        "W6 module params",
    )

    text = must_replace(
        text,
        "\tconst char *w4b_phase;\n};\n",
        "\tconst char *w4b_phase;\n"
        "\tstruct delayed_work w6_deferred_reinit;\n"
        "\tbool w6_second_reinit_pending;\n"
        "};\n",
        "W6 struct fields",
    )

    text = must_replace(
        text,
        "static s32 tas_io_init(struct device *dev, struct sdw_slave *slave);\n"
        "static s32 tas2783_fw_reinit(struct device *dev, struct sdw_slave *slave);\n",
        "static s32 tas_io_init(struct device *dev, struct sdw_slave *slave);\n"
        "static s32 tas2783_fw_reinit(struct device *dev, struct sdw_slave *slave);\n"
        "static void tas2783_w6_cancel_second_reinit(struct tas2783_prv *tas_dev);\n"
        "static void tas2783_w6_arm_second_reinit(struct tas2783_prv *tas_dev);\n"
        "static s32 tas2783_w2_force_fw_reinit(struct device *dev, struct sdw_slave *slave,\n"
        "\t\t\t\t\t      const char *when);\n",
        "W6 forward declarations",
    )

    w6_helpers = r'''
static void tas2783_w6_deferred_reinit_work(struct work_struct *work)
{
	struct tas2783_prv *tas_dev = container_of(to_delayed_work(work),
						   struct tas2783_prv,
						   w6_deferred_reinit);
	struct sdw_slave *slave = tas_dev->sdw_peripheral;
	struct device *dev = &slave->dev;
	s32 ret;

	if (tas_dev->status != SDW_SLAVE_ATTACHED)
		return;

	W4B_PHASE_SET(tas_dev, "W6_DEFERRED");
	dev_info(dev, "W6 ctx=deferred fn=fw_reinit uid=%d delay_ms=%u\n",
		 tas2783_w4_uid(tas_dev), deferred_reinit_ms);
	ret = tas2783_fw_reinit(dev, slave);
	dev_info(dev, "W6 ctx=deferred fn=fw_reinit uid=%d ret=%d\n",
		 tas2783_w4_uid(tas_dev), ret);
	tas_dev->w6_second_reinit_pending = false;
}

static void tas2783_w6_cancel_second_reinit(struct tas2783_prv *tas_dev)
{
	if (!tas_dev)
		return;

	cancel_delayed_work_sync(&tas_dev->w6_deferred_reinit);
	tas_dev->w6_second_reinit_pending = false;
}

static void tas2783_w6_arm_second_reinit(struct tas2783_prv *tas_dev)
{
	if (!tas_dev || !tas_dev->dev)
		return;

	if (deferred_reinit_on_port_prep) {
		tas_dev->w6_second_reinit_pending = true;
		dev_info(tas_dev->dev,
			 "W6 ctx=arm fn=port_prep_reinit uid=%d\n",
			 tas2783_w4_uid(tas_dev));
		return;
	}

	if (!deferred_reinit_ms)
		return;

	cancel_delayed_work_sync(&tas_dev->w6_deferred_reinit);
	schedule_delayed_work(&tas_dev->w6_deferred_reinit,
			      msecs_to_jiffies(deferred_reinit_ms));
	dev_info(tas_dev->dev,
		 "W6 ctx=schedule fn=deferred_reinit uid=%d delay_ms=%u\n",
		 tas2783_w4_uid(tas_dev), deferred_reinit_ms);
}

static s32 tas2783_w2_force_fw_reinit(struct device *dev, struct sdw_slave *slave,
				      const char *when)
{
	struct tas2783_prv *tas_dev = dev_get_drvdata(dev);
	u8 uid = tas2783_w4_uid(tas_dev);
	s32 ret;

	tas2783_w4_life(dev, uid, when, "force_fw_reinit");
	dev_info(dev, "W2 ctx=tas fn=force_fw_reinit when=%s uid=%d\n", when, uid);
	tas_dev->post_system_sleep = false;
	ret = tas2783_fw_reinit(dev, slave);
	tas2783_w6_arm_second_reinit(tas_dev);
	return ret;
}

'''
    text = must_replace(
        text,
        "static s32 tas_update_status(struct sdw_slave *slave,\n",
        w6_helpers + "static s32 tas_update_status(struct sdw_slave *slave,\n",
        "W6 helpers before update_status",
    )

    text = must_replace(
        text,
        "\tif (tas_dev->post_system_sleep &&\n"
        "\t    tas_dev->status == SDW_SLAVE_ATTACHED) {\n"
        "\t\ttas2783_w4_life(dev, uid, \"resume\", \"force_fw_reinit\");\n"
        "\t\tdev_info(dev,\n"
        "\t\t\t \"W2 ctx=tas fn=force_fw_reinit when=resume uid=%d\\n\",\n"
        "\t\t\t tas_dev->sdw_peripheral->id.unique_id);\n"
        "\t\ttas_dev->post_system_sleep = false;\n"
        "\t\treturn tas2783_fw_reinit(dev, slave);\n"
        "\t}\n",
        "\tif (tas_dev->post_system_sleep &&\n"
        "\t    tas_dev->status == SDW_SLAVE_ATTACHED)\n"
        "\t\treturn tas2783_w2_force_fw_reinit(dev, slave, \"resume\");\n",
        "W2 resume path",
    )

    text = must_replace(
        text,
        "\tif (status == SDW_SLAVE_ATTACHED && tas_dev->post_system_sleep) {\n"
        "\t\tW4B_PHASE_SET(tas_dev, \"RESUME\");\n"
        "\t\ttas2783_w4_life(dev, tas_dev->sdw_peripheral->id.unique_id, \"update_status\", \"force_fw_reinit\");\n"
        "\t\tdev_info(dev,\n"
        "\t\t\t \"W2 ctx=tas fn=force_fw_reinit when=update_status uid=%d\\n\",\n"
        "\t\t\t tas_dev->sdw_peripheral->id.unique_id);\n"
        "\t\ttas_dev->post_system_sleep = false;\n"
        "\t\tregcache_cache_only(tas_dev->regmap, false);\n"
        "\t\tregcache_sync(tas_dev->regmap);\n"
        "\t\treturn tas2783_fw_reinit(&slave->dev, slave);\n"
        "\t}\n",
        "\tif (status == SDW_SLAVE_ATTACHED && tas_dev->post_system_sleep) {\n"
        "\t\tW4B_PHASE_SET(tas_dev, \"RESUME\");\n"
        "\t\tregcache_cache_only(tas_dev->regmap, false);\n"
        "\t\tregcache_sync(tas_dev->regmap);\n"
        "\t\treturn tas2783_w2_force_fw_reinit(&slave->dev, slave, \"update_status\");\n"
        "\t}\n",
        "W2 update_status path",
    )

    text = must_replace(
        text,
        "\tif (tas_dev) {\n"
        "\t\tW4B_PHASE_SET(tas_dev, \"SUSPEND\");\n"
        "\t\ttas2783_w4_life(dev, tas2783_w4_uid(tas_dev),\n"
        "\t\t\t\t\"system_suspend\", \"enter\");\n"
        "\t}\n",
        "\tif (tas_dev) {\n"
        "\t\tW4B_PHASE_SET(tas_dev, \"SUSPEND\");\n"
        "\t\ttas2783_w4_life(dev, tas2783_w4_uid(tas_dev),\n"
        "\t\t\t\t\"system_suspend\", \"enter\");\n"
        "\t\ttas2783_w6_cancel_second_reinit(tas_dev);\n"
        "\t}\n",
        "W6 cancel on suspend",
    )

    text = must_replace(
        text,
        "\tcase SDW_OPS_PORT_PRE_PREP:\n"
        "\t\ttas2783_w4_life(dev, uid, \"port_prep\", \"pre_prep\");\n"
        "\t\tW4B_PHASE_SET(tas_dev, \"RUNTIME\");\n"
        "\t\tret = tas2783_w4b_sdw_write(tas_dev, addr, prep_ch->ch_mask, __func__);\n",
        "\tcase SDW_OPS_PORT_PRE_PREP:\n"
        "\t\ttas2783_w4_life(dev, uid, \"port_prep\", \"pre_prep\");\n"
        "\t\tW4B_PHASE_SET(tas_dev, \"RUNTIME\");\n"
        "\t\tif (deferred_reinit_on_port_prep && tas_dev->w6_second_reinit_pending) {\n"
        "\t\t\ts32 w6_ret;\n"
        "\n"
        "\t\t\ttas_dev->w6_second_reinit_pending = false;\n"
        "\t\t\tcancel_delayed_work_sync(&tas_dev->w6_deferred_reinit);\n"
        "\t\t\tW4B_PHASE_SET(tas_dev, \"W6_PORT_PREP\");\n"
        "\t\t\tdev_info(dev,\n"
        "\t\t\t\t \"W6 ctx=port_prep fn=fw_reinit uid=%d port=%d\\n\",\n"
        "\t\t\t\t uid, prep_ch->num);\n"
        "\t\t\tw6_ret = tas2783_fw_reinit(dev, slave);\n"
        "\t\t\tdev_info(dev,\n"
        "\t\t\t\t \"W6 ctx=port_prep fn=fw_reinit uid=%d ret=%d\\n\",\n"
        "\t\t\t\t uid, w6_ret);\n"
        "\t\t}\n"
        "\t\tret = tas2783_w4b_sdw_write(tas_dev, addr, prep_ch->ch_mask, __func__);\n",
        "W6 port_prep hook",
    )

    text = must_replace(
        text,
        "\tinit_waitqueue_head(&tas_dev->fw_wait);\n"
        "\tdev_set_drvdata(dev, tas_dev);\n",
        "\tinit_waitqueue_head(&tas_dev->fw_wait);\n"
        "\tINIT_DELAYED_WORK(&tas_dev->w6_deferred_reinit,\n"
        "\t\t\t  tas2783_w6_deferred_reinit_work);\n"
        "\tdev_set_drvdata(dev, tas_dev);\n",
        "W6 probe init",
    )

    text = must_replace(
        text,
        "\tpm_runtime_disable(tas_dev->dev);\n"
        "\ttas_remove(tas_dev);\n",
        "\ttas2783_w6_cancel_second_reinit(tas_dev);\n"
        "\tpm_runtime_disable(tas_dev->dev);\n"
        "\ttas_remove(tas_dev);\n",
        "W6 remove cancel",
    )

    path.write_text(text)
    print(f"W6 applied to {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
