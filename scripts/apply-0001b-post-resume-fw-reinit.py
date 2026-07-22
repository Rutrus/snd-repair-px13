#!/usr/bin/env python3
"""Evolve 0001 → 0001b: dual-trigger post-resume fw_reinit (hw_params | delayed_work).

Requires 0001 already applied (resume_playback_reinit_pending + post_sleep helper).
Implements a single run_once() claimed by either trigger; schedules post-resume
completion work (100 ms / ~HZ/10) so open PipeWire streams recover without a
new hw_params.
"""
from __future__ import annotations

import sys
from pathlib import Path

MARKER_FAIL = "post-sleep playback fw_reinit failed"
MARKER_OK = "snd_repair post-resume fw_reinit"

RUN_ONCE_BLOCK = r"""
/* 0001b: second post-sleep fw_reinit — one claim, two triggers (hw_params | work). */
#define TAS2783_POST_RESUME_COMPLETION_MS 100

static s32 tas2783_run_post_resume_fw_reinit_once(struct tas2783_prv *tas_dev)
{
	struct sdw_slave *slave;
	s32 ret;

	if (!tas_dev || !tas_dev->resume_playback_reinit_pending)
		return 0;
	if (tas_dev->status != SDW_SLAVE_ATTACHED)
		return 0;
	/* First resume fw_reinit must have finished loading FW. */
	if (!tas_dev->fw_dl_success)
		return 0;

	tas_dev->resume_playback_reinit_pending = false;
	cancel_delayed_work(&tas_dev->post_resume_fw_reinit);

	slave = tas_dev->sdw_peripheral;
	ret = tas2783_fw_reinit(tas_dev->dev, slave);
	if (ret) {
		dev_warn(tas_dev->dev,
			 "post-sleep playback fw_reinit failed: %d\n", ret);
		return ret;
	}
	dev_info(tas_dev->dev, "snd_repair post-resume fw_reinit\n");
	return 0;
}

static void tas2783_post_resume_fw_reinit_work(struct work_struct *work)
{
	struct tas2783_prv *tas_dev =
		container_of(to_delayed_work(work), struct tas2783_prv,
			     post_resume_fw_reinit);

	tas2783_run_post_resume_fw_reinit_once(tas_dev);
}

"""

OLD_HELPER = """static s32 tas2783_post_sleep_resume_fw_reinit(struct device *dev,
					       struct sdw_slave *slave)
{
	struct tas2783_prv *tas_dev = dev_get_drvdata(dev);
	s32 ret;

	if (!tas_dev)
		return -ENODEV;

	tas_dev->post_system_sleep = false;
	ret = tas2783_fw_reinit(dev, slave);
	if (!ret)
		tas_dev->resume_playback_reinit_pending = true;

	return ret;
}
"""

NEW_HELPER = """static s32 tas2783_post_sleep_resume_fw_reinit(struct device *dev,
					       struct sdw_slave *slave)
{
	struct tas2783_prv *tas_dev = dev_get_drvdata(dev);
	s32 ret;

	if (!tas_dev)
		return -ENODEV;

	tas_dev->post_system_sleep = false;
	ret = tas2783_fw_reinit(dev, slave);
	if (!ret) {
		tas_dev->resume_playback_reinit_pending = true;
		schedule_delayed_work(&tas_dev->post_resume_fw_reinit,
				      msecs_to_jiffies(TAS2783_POST_RESUME_COMPLETION_MS));
	}

	return ret;
}
"""

OLD_HW = """\tif (tas_dev->resume_playback_reinit_pending &&
\t    tas_dev->status == SDW_SLAVE_ATTACHED) {
\t\ttas_dev->resume_playback_reinit_pending = false;
\t\tret = tas2783_fw_reinit(&sdw_peripheral->dev, sdw_peripheral);
\t\tif (ret) {
\t\t\tdev_warn(tas_dev->dev,
\t\t\t\t "post-sleep playback fw_reinit failed: %d\\n", ret);
\t\t\treturn ret;
\t\t}
\t}
"""

NEW_HW = """\tret = tas2783_run_post_resume_fw_reinit_once(tas_dev);
\tif (ret)
\t\treturn ret;
"""


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

    if MARKER_OK in text and "tas2783_run_post_resume_fw_reinit_once" in text:
        print("0001b post-resume dual-trigger already present")
        return 0

    if "resume_playback_reinit_pending" not in text or MARKER_FAIL not in text:
        raise SystemExit("ERROR: apply 0001 first (resume_playback_reinit_pending missing)")

    # struct field
    if "post_resume_fw_reinit" not in text.split("struct tas2783_prv")[1][:800]:
        text = must_replace(
            text,
            "\tbool resume_playback_reinit_pending;\n};\n",
            "\tbool resume_playback_reinit_pending;\n"
            "\tstruct delayed_work post_resume_fw_reinit;\n};\n",
            "struct delayed_work field",
        )

    # insert run_once + work before post_sleep helper
    if "tas2783_run_post_resume_fw_reinit_once" not in text:
        text = must_replace(
            text,
            "static s32 tas2783_post_sleep_resume_fw_reinit(struct device *dev,\n",
            RUN_ONCE_BLOCK
            + "static s32 tas2783_post_sleep_resume_fw_reinit(struct device *dev,\n",
            "insert run_once",
        )

    # schedule from helper (small anchor — ignore signature wrapping)
    sched_old = (
        "\ttas_dev->post_system_sleep = false;\n"
        "\tret = tas2783_fw_reinit(dev, slave);\n"
        "\tif (!ret)\n"
        "\t\ttas_dev->resume_playback_reinit_pending = true;\n"
        "\n"
        "\treturn ret;\n"
        "}\n"
    )
    sched_new = (
        "\ttas_dev->post_system_sleep = false;\n"
        "\tret = tas2783_fw_reinit(dev, slave);\n"
        "\tif (!ret) {\n"
        "\t\ttas_dev->resume_playback_reinit_pending = true;\n"
        "\t\tschedule_delayed_work(&tas_dev->post_resume_fw_reinit,\n"
        "\t\t\t      msecs_to_jiffies(TAS2783_POST_RESUME_COMPLETION_MS));\n"
        "\t}\n"
        "\n"
        "\treturn ret;\n"
        "}\n"
    )
    if "schedule_delayed_work(&tas_dev->post_resume_fw_reinit" not in text:
        text = must_replace(text, sched_old, sched_new, "schedule from helper")

    # hw_params uses run_once
    if "tas2783_run_post_resume_fw_reinit_once(tas_dev)" not in text:
        if OLD_HW not in text:
            raise SystemExit("ERROR: 0001 hw_params block not found")
        text = text.replace(OLD_HW, NEW_HW, 1)

    # INIT_DELAYED_WORK in probe
    if "INIT_DELAYED_WORK(&tas_dev->post_resume_fw_reinit" not in text:
        if "mutex_init(&tas_dev->pde_lock);" in text:
            text = must_replace(
                text,
                "mutex_init(&tas_dev->pde_lock);",
                "mutex_init(&tas_dev->pde_lock);\n"
                "\tINIT_DELAYED_WORK(&tas_dev->post_resume_fw_reinit,\n"
                "\t\t\t  tas2783_post_resume_fw_reinit_work);",
                "INIT_DELAYED_WORK probe",
            )
        else:
            raise SystemExit("ERROR: probe mutex_init anchor missing")

    # cancel on system suspend when clearing pending
    if text.count("cancel_delayed_work_sync(&tas_dev->post_resume_fw_reinit)") < 1:
        text = must_replace(
            text,
            "\t\ttas_dev->resume_playback_reinit_pending = false;\n"
            "\t\ttas_dev->hw_init = false;\n",
            "\t\ttas_dev->resume_playback_reinit_pending = false;\n"
            "\t\tcancel_delayed_work_sync(&tas_dev->post_resume_fw_reinit);\n"
            "\t\ttas_dev->hw_init = false;\n",
            "suspend cancel delayed",
        )

    # cancel on UNATTACHED
    unatt_old = (
        "\tif (status == SDW_SLAVE_UNATTACHED) {\n"
        "\t\ttas_dev->hw_init = false;\n"
        "\t\ttas_dev->resume_playback_reinit_pending = false;\n"
        "\t}\n"
    )
    unatt_new = (
        "\tif (status == SDW_SLAVE_UNATTACHED) {\n"
        "\t\ttas_dev->hw_init = false;\n"
        "\t\ttas_dev->resume_playback_reinit_pending = false;\n"
        "\t\tcancel_delayed_work_sync(&tas_dev->post_resume_fw_reinit);\n"
        "\t}\n"
    )
    if unatt_old in text:
        text = text.replace(unatt_old, unatt_new, 1)
    elif "cancel_delayed_work_sync(&tas_dev->post_resume_fw_reinit)" not in text.split(
        "SDW_SLAVE_UNATTACHED", 1
    )[1][:500]:
        raise SystemExit("ERROR: UNATTACHED clear-pending block missing")

    # remove
    if "cancel_delayed_work_sync(&tas_dev->post_resume_fw_reinit)" not in text.split(
        "tas_remove", 1
    )[1][:400]:
        text = must_replace(
            text,
            "static void tas_remove(struct tas2783_prv *tas_dev)\n{\n"
            "\tsnd_soc_unregister_component(tas_dev->dev);\n"
            "}\n",
            "static void tas_remove(struct tas2783_prv *tas_dev)\n{\n"
            "\tcancel_delayed_work_sync(&tas_dev->post_resume_fw_reinit);\n"
            "\tsnd_soc_unregister_component(tas_dev->dev);\n"
            "}\n",
            "remove cancel",
        )

    path.write_text(text)
    print(f"0001b post-resume dual-trigger applied to {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
