#!/usr/bin/env python3
"""Apply W8 context-triggered 2nd fw_reinit (hw_params / dapm POST_PMU) on tas2783-sdw.c."""
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
        print("ERROR: W6 not present", file=sys.stderr)
        return 1
    if "deferred_reinit_on_hw_params" in text:
        print("W8 already present")
        return 0

    text = must_replace(
        text,
        'MODULE_PARM_DESC(deferred_reinit_on_port_prep,\n'
        '\t\t "W6 experiment: 2nd fw_reinit on first port PRE_PREP after W2");\n',
        'MODULE_PARM_DESC(deferred_reinit_on_port_prep,\n'
        '\t\t "W6 experiment: 2nd fw_reinit on first port PRE_PREP after W2");\n\n'
        'static bool deferred_reinit_on_hw_params;\n'
        'module_param(deferred_reinit_on_hw_params, bool, 0644);\n'
        'MODULE_PARM_DESC(deferred_reinit_on_hw_params,\n'
        '\t\t "W8: 2nd fw_reinit on first hw_params after W2 (0 ms, event context)");\n\n'
        'static bool deferred_reinit_on_dapm_pmu;\n'
        'module_param(deferred_reinit_on_dapm_pmu, bool, 0644);\n'
        'MODULE_PARM_DESC(deferred_reinit_on_dapm_pmu,\n'
        '\t\t "W8: 2nd fw_reinit on first DAPM POST_PMU (FU21) after W2");\n',
        "W8 module params",
    )

    text = must_replace(
        text,
        "\tbool w6_second_reinit_pending;\n};\n",
        "\tbool w6_second_reinit_pending;\n"
        "\tbool w8_dapm_reinit_done;\n};\n",
        "W8 struct field",
    )

    text = must_replace(
        text,
        "static void tas2783_w7_ts_once_port_prep(struct device *dev, u8 uid);\n",
        "static void tas2783_w7_ts_once_port_prep(struct device *dev, u8 uid);\n"
        "static s32 tas2783_w8_second_fw_reinit(struct device *dev, struct sdw_slave *slave,\n"
        "\t\t\t\t\t     const char *when);\n",
        "W8 forward decl",
    )

    w8_helper = r'''
static s32 tas2783_w8_second_fw_reinit(struct device *dev, struct sdw_slave *slave,
				       const char *when)
{
	struct tas2783_prv *tas_dev = dev_get_drvdata(dev);
	u8 uid = tas2783_w4_uid(tas_dev);
	s32 ret;

	if (!tas_dev || tas_dev->status != SDW_SLAVE_ATTACHED)
		return -ENODEV;

	tas_dev->w6_second_reinit_pending = false;
	cancel_delayed_work_sync(&tas_dev->w6_deferred_reinit);
	W4B_PHASE_SET(tas_dev, "W8_CONTEXT");
	tas2783_w7_ts(dev, uid, "w8_fw_reinit_start");
	dev_info(dev, "W8 ctx=%s fn=fw_reinit uid=%d\n", when, uid);
	ret = tas2783_fw_reinit(dev, slave);
	dev_info(dev, "W8 ctx=%s fn=fw_reinit uid=%d ret=%d\n", when, uid, ret);
	tas2783_w7_ts(dev, uid, ret ? "w8_fw_reinit_end_err" : "w8_fw_reinit_end");
	return ret;
}

'''
    text = must_replace(
        text,
        "static void tas2783_w6_deferred_reinit_work(struct work_struct *work)\n",
        w8_helper + "static void tas2783_w6_deferred_reinit_work(struct work_struct *work)\n",
        "W8 helper",
    )

    text = must_replace(
        text,
        "\tif (deferred_reinit_on_port_prep) {\n"
        "\t\ttas_dev->w6_second_reinit_pending = true;\n"
        "\t\tdev_info(tas_dev->dev,\n"
        "\t\t\t \"W6 ctx=arm fn=port_prep_reinit uid=%d\\n\",\n"
        "\t\t\t tas2783_w4_uid(tas_dev));\n"
        "\t\treturn;\n"
        "\t}\n",
        "\tif (deferred_reinit_on_hw_params) {\n"
        "\t\ttas_dev->w6_second_reinit_pending = true;\n"
        "\t\ttas_dev->w8_dapm_reinit_done = false;\n"
        "\t\tdev_info(tas_dev->dev,\n"
        "\t\t\t \"W8 ctx=arm fn=hw_params_reinit uid=%d\\n\",\n"
        "\t\t\t tas2783_w4_uid(tas_dev));\n"
        "\t\treturn;\n"
        "\t}\n\n"
        "\tif (deferred_reinit_on_dapm_pmu) {\n"
        "\t\ttas_dev->w6_second_reinit_pending = true;\n"
        "\t\ttas_dev->w8_dapm_reinit_done = false;\n"
        "\t\tdev_info(tas_dev->dev,\n"
        "\t\t\t \"W8 ctx=arm fn=dapm_pmu_reinit uid=%d\\n\",\n"
        "\t\t\t tas2783_w4_uid(tas_dev));\n"
        "\t\treturn;\n"
        "\t}\n\n"
        "\tif (deferred_reinit_on_port_prep) {\n"
        "\t\ttas_dev->w6_second_reinit_pending = true;\n"
        "\t\ttas_dev->w8_dapm_reinit_done = false;\n"
        "\t\tdev_info(tas_dev->dev,\n"
        "\t\t\t \"W8 ctx=arm fn=port_prep_reinit uid=%d\\n\",\n"
        "\t\t\t tas2783_w4_uid(tas_dev));\n"
        "\t\treturn;\n"
        "\t}\n",
        "W8 arm modes",
    )

    text = must_replace(
        text,
        "\ttas_dev->w6_second_reinit_pending = false;\n"
        "}\n\n"
        "static void tas2783_w6_arm_second_reinit",
        "\ttas_dev->w6_second_reinit_pending = false;\n"
        "\ttas_dev->w8_dapm_reinit_done = false;\n"
        "}\n\n"
        "static void tas2783_w6_arm_second_reinit",
        "W8 reset dapm flag on cancel",
    )

    text = must_replace(
        text,
        "\tW4B_PHASE_SET(tas_dev, \"RUNTIME\");\n"
        "\ttas2783_w7_ts_once_hw_params(tas_dev->dev, uid);\n"
        "\ttas2783_w4_life(tas_dev->dev, uid, \"hw_params\", \"enter\");\n",
        "\tW4B_PHASE_SET(tas_dev, \"RUNTIME\");\n"
        "\ttas2783_w7_ts_once_hw_params(tas_dev->dev, uid);\n"
        "\tif (deferred_reinit_on_hw_params && tas_dev->w6_second_reinit_pending) {\n"
        "\t\ts32 w8_ret = tas2783_w8_second_fw_reinit(&sdw_peripheral->dev,\n"
        "\t\t\t\t\t\t\t sdw_peripheral, \"hw_params\");\n"
        "\t\tif (w8_ret)\n"
        "\t\t\tdev_warn(tas_dev->dev, \"W8 hw_params reinit failed: %d\\n\", w8_ret);\n"
        "\t}\n"
        "\ttas2783_w4_life(tas_dev->dev, uid, \"hw_params\", \"enter\");\n",
        "W8 hw_params trigger",
    )

    text = must_replace(
        text,
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
        "\t\t}\n",
        "\t\tif (deferred_reinit_on_port_prep && tas_dev->w6_second_reinit_pending) {\n"
        "\t\t\ts32 w8_ret = tas2783_w8_second_fw_reinit(dev, slave, \"port_prep\");\n"
        "\n"
        "\t\t\tif (w8_ret)\n"
        "\t\t\t\tdev_err(dev, \"W8 port_prep reinit failed: %d\\n\", w8_ret);\n"
        "\t\t}\n",
        "W8 port_prep uses helper",
    )

    text = must_replace(
        text,
        "\tcase SND_SOC_DAPM_POST_PMU:\n"
        "\t\tmute = 0;\n"
        "\t\tbreak;\n"
        "\n"
        "\tcase SND_SOC_DAPM_PRE_PMD:\n"
        "\t\tmute = 1;\n"
        "\t\tbreak;\n"
        "\t}\n"
        "\n"
        "\treturn tas2783_w4_sdw_write(tas_dev,\n"
        "\t\t\t       SDW_SDCA_CTL(1, TAS2783_SDCA_ENT_FU21,\n",
        "\tcase SND_SOC_DAPM_POST_PMU:\n"
        "\t\tmute = 0;\n"
        "\t\tif (deferred_reinit_on_dapm_pmu && tas_dev->w6_second_reinit_pending &&\n"
        "\t\t    !tas_dev->w8_dapm_reinit_done && tas_dev->sdw_peripheral) {\n"
        "\t\t\ttas_dev->w8_dapm_reinit_done = true;\n"
        "\t\t\ttas2783_w8_second_fw_reinit(tas_dev->dev, tas_dev->sdw_peripheral,\n"
        "\t\t\t\t\t\t    \"dapm_post_pmu\");\n"
        "\t\t}\n"
        "\t\tbreak;\n"
        "\n"
        "\tcase SND_SOC_DAPM_PRE_PMD:\n"
        "\t\tmute = 1;\n"
        "\t\tbreak;\n"
        "\t}\n"
        "\n"
        "\treturn tas2783_w4_sdw_write(tas_dev,\n"
        "\t\t\t       SDW_SDCA_CTL(1, TAS2783_SDCA_ENT_FU21,\n",
        "W8 dapm POST_PMU trigger",
    )

    path.write_text(text)
    print(f"W8 applied to {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
