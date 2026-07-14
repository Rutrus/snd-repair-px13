#!/usr/bin/env python3
"""Apply upstream candidate: one-shot fw_reinit on first hw_params after system sleep."""
from __future__ import annotations

import sys
from pathlib import Path

UPSTREAM_HW_PARAMS = """\
\tif (tas_dev->resume_playback_reinit_pending &&
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

POST_SLEEP_HELPER = """
static s32 tas2783_post_sleep_resume_fw_reinit(struct device *dev,
\t\t\t\t\t\t       struct sdw_slave *slave)
{
\tstruct tas2783_prv *tas_dev = dev_get_drvdata(dev);
\ts32 ret;

\tif (!tas_dev)
\t\treturn -ENODEV;

\ttas_dev->post_system_sleep = false;
\tret = tas2783_fw_reinit(dev, slave);
\tif (!ret)
\t\ttas_dev->resume_playback_reinit_pending = true;

\treturn ret;
}

"""


def must_replace(text: str, old: str, new: str, label: str, count: int = 1) -> str:
    if old not in text:
        raise SystemExit(f"ERROR: anchor missing for {label}")
    return text.replace(old, new, count)


def add_struct_field(text: str) -> str:
    if "resume_playback_reinit_pending" in text:
        return text
    if "w8_dapm_reinit_done;" in text:
        return must_replace(
            text,
            "\tbool w8_dapm_reinit_done;\n};\n",
            "\tbool w8_dapm_reinit_done;\n"
            "\tbool resume_playback_reinit_pending;\n"
            "};\n",
            "struct field after w8_dapm_reinit_done",
        )
    if "post_system_sleep;" in text:
        return must_replace(
            text,
            "\tbool post_system_sleep;\n",
            "\tbool post_system_sleep;\n"
            "\tbool resume_playback_reinit_pending;\n",
            "struct field after post_system_sleep",
            1,
        )
    return must_replace(
        text,
        "\tbool fw_dl_success;\n};\n",
        "\tbool fw_dl_success;\n"
        "\tbool post_system_sleep;\n"
        "\tbool resume_playback_reinit_pending;\n"
        "};\n",
        "struct field vanilla",
    )


def add_post_sleep_helper(text: str) -> str:
    if "tas2783_post_sleep_resume_fw_reinit" in text:
        return text
    if "tas2783_w2_force_fw_reinit" in text:
        return text  # w2_force sets resume_playback_reinit_pending directly
    return must_replace(
        text,
        "static s32 tas2783_fw_reinit(struct device *dev, struct sdw_slave *slave);\n",
        "static s32 tas2783_fw_reinit(struct device *dev, struct sdw_slave *slave);\n"
        + POST_SLEEP_HELPER,
        "post_sleep helper",
    )


def clear_pending_on_suspend(text: str) -> str:
    if "resume_playback_reinit_pending = false" in text and "system_suspend" in text:
        # may already be set via w6_cancel only — still ensure explicit clear
        pass
    if "\t\ttas_dev->post_system_sleep = true;\n" in text:
        if "resume_playback_reinit_pending = false" not in text.split("post_system_sleep = true")[0][-400:]:
            text = must_replace(
                text,
                "\t\ttas_dev->post_system_sleep = true;\n",
                "\t\ttas_dev->post_system_sleep = true;\n"
                "\t\ttas_dev->resume_playback_reinit_pending = false;\n",
                "suspend clear pending",
                1,
            )
    elif "\tif (tas_dev && tas_dev->hw_init) {\n" in text:
        text = must_replace(
            text,
            "\tif (tas_dev && tas_dev->hw_init) {\n"
            "\t\ttas_dev->hw_init = false;\n",
            "\tif (tas_dev) {\n"
            "\t\ttas_dev->post_system_sleep = true;\n"
            "\t\ttas_dev->resume_playback_reinit_pending = false;\n"
            "\t\ttas_dev->hw_init = false;\n",
            "suspend post_system_sleep vanilla",
        )
    return text


def patch_w6_cancel(text: str) -> str:
    if "tas2783_w6_cancel_second_reinit" not in text:
        return text
    old = (
        "\ttas_dev->w6_second_reinit_pending = false;\n"
        "\ttas_dev->w8_dapm_reinit_done = false;\n"
        "}\n"
    )
    new = (
        "\ttas_dev->w6_second_reinit_pending = false;\n"
        "\ttas_dev->w8_dapm_reinit_done = false;\n"
        "\ttas_dev->resume_playback_reinit_pending = false;\n"
        "}\n"
    )
    if old in text and "resume_playback_reinit_pending = false" not in old:
        return text.replace(old, new, 1)
    return text


def patch_w2_force(text: str) -> str:
    if "tas2783_w2_force_fw_reinit" not in text:
        return text
    old = (
        "\tret = tas2783_fw_reinit(dev, slave);\n"
        "\ttas2783_w7_ts(dev, uid, ret ? \"w2_fw_reinit_end_err\" : \"w2_fw_reinit_end\");\n"
        "\ttas2783_w6_arm_second_reinit(tas_dev);\n"
        "\treturn ret;\n"
    )
    new = (
        "\tret = tas2783_fw_reinit(dev, slave);\n"
        "\ttas2783_w7_ts(dev, uid, ret ? \"w2_fw_reinit_end_err\" : \"w2_fw_reinit_end\");\n"
        "\tif (!ret)\n"
        "\t\ttas_dev->resume_playback_reinit_pending = true;\n"
        "\ttas2783_w6_arm_second_reinit(tas_dev);\n"
        "\treturn ret;\n"
    )
    if old in text:
        return text.replace(old, new, 1)
    return text


def patch_hw_params(text: str) -> str:
    if "post-sleep playback fw_reinit failed" in text:
        return text

    # W7 + W8 experimental tree
    w7_anchor = (
        "\ttas2783_w7_ts_once_hw_params(tas_dev->dev, uid);\n"
        "\tif (deferred_reinit_on_hw_params && tas_dev->w6_second_reinit_pending) {\n"
    )
    if w7_anchor in text:
        return must_replace(
            text,
            w7_anchor,
            "\ttas2783_w7_ts_once_hw_params(tas_dev->dev, uid);\n"
            + UPSTREAM_HW_PARAMS
            + "\tif (deferred_reinit_on_hw_params && tas_dev->w6_second_reinit_pending) {\n",
            "hw_params W7/W8 tree",
        )

    # W4 trace tree without W7
    w4_anchor = (
        "\tstruct sdw_slave *sdw_peripheral = tas_dev->sdw_peripheral;\n"
        "\ts32 ret, retry = 3;\n"
        "\tu8 uid = tas2783_w4_uid(tas_dev);\n\n"
        "\ttas2783_w4_life(tas_dev->dev, uid, \"hw_params\", \"enter\");\n"
    )
    if w4_anchor in text:
        return must_replace(
            text,
            w4_anchor,
            "\tstruct sdw_slave *sdw_peripheral = tas_dev->sdw_peripheral;\n"
            "\ts32 ret, retry = 3;\n"
            "\tu8 uid = tas2783_w4_uid(tas_dev);\n\n"
            + UPSTREAM_HW_PARAMS
            + "\ttas2783_w4_life(tas_dev->dev, uid, \"hw_params\", \"enter\");\n",
            "hw_params W4 tree",
        )

    return must_replace(
        text,
        "\tstruct sdw_slave *sdw_peripheral = tas_dev->sdw_peripheral;\n"
        "\ts32 ret, retry = 3;\n\n"
        "\tif (!tas_dev->fw_dl_success && !tas_dev->fw_dl_task_done &&\n",
        "\tstruct sdw_slave *sdw_peripheral = tas_dev->sdw_peripheral;\n"
        "\ts32 ret, retry = 3;\n\n"
        + UPSTREAM_HW_PARAMS
        + "\tif (!tas_dev->fw_dl_success && !tas_dev->fw_dl_task_done &&\n",
        "hw_params vanilla",
    )


def patch_resume_paths(text: str) -> str:
    if "tas2783_post_sleep_resume_fw_reinit" in text and "tas2783_w2_force_fw_reinit" in text:
        return text  # W2 experimental tree arms pending inside w2_force

    blocks = (
        (
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
            "\t\treturn tas2783_post_sleep_resume_fw_reinit(dev, slave);\n",
        ),
        (
            "\tif (tas_dev->post_system_sleep &&\n"
            "\t    tas_dev->status == SDW_SLAVE_ATTACHED) {\n"
            "\t\tdev_info(dev,\n"
            "\t\t\t \"W2 ctx=tas fn=force_fw_reinit when=resume uid=%d\\n\",\n"
            "\t\t\t tas_dev->sdw_peripheral->id.unique_id);\n"
            "\t\ttas_dev->post_system_sleep = false;\n"
            "\t\treturn tas2783_fw_reinit(dev, slave);\n"
            "\t}\n",
            "\tif (tas_dev->post_system_sleep &&\n"
            "\t    tas_dev->status == SDW_SLAVE_ATTACHED)\n"
            "\t\treturn tas2783_post_sleep_resume_fw_reinit(dev, slave);\n",
        ),
        (
            "\tif (tas_dev->post_system_sleep &&\n"
            "\t    tas_dev->status == SDW_SLAVE_ATTACHED)\n"
            "\t\treturn tas2783_w2_force_fw_reinit(dev, slave, \"resume\");\n",
            "\t\treturn tas2783_w2_force_fw_reinit(dev, slave, \"resume\");\n",  # noop dup guard
        ),
    )

    if "\treturn tas2783_w2_force_fw_reinit(dev, slave, \"resume\");\n" in text:
        return text

    for old, new in blocks[:2]:
        if old in text:
            return text.replace(old, new, 1)

    if "regmap_sync:\n" in text and "tas2783_post_sleep_resume_fw_reinit(dev, slave)" not in text:
        text = must_replace(
            text,
            "regmap_sync:\n"
            "\tregcache_cache_only(tas_dev->regmap, false);\n"
            "\tregcache_sync(tas_dev->regmap);\n\n",
            "regmap_sync:\n"
            "\tregcache_cache_only(tas_dev->regmap, false);\n"
            "\tregcache_sync(tas_dev->regmap);\n\n"
            "\tif (tas_dev->post_system_sleep &&\n"
            "\t    tas_dev->status == SDW_SLAVE_ATTACHED)\n"
            "\t\treturn tas2783_post_sleep_resume_fw_reinit(dev, slave);\n\n",
            "resume hook",
        )
    return text


def patch_update_status(text: str) -> str:
    if "tas2783_w2_force_fw_reinit" in text:
        if "resume_playback_reinit_pending = false" not in text.split("SDW_SLAVE_UNATTACHED")[1][:500]:
            text = must_replace(
                text,
                "\tif (status == SDW_SLAVE_UNATTACHED)\n"
                "\t\ttas_dev->hw_init = false;\n",
                "\tif (status == SDW_SLAVE_UNATTACHED) {\n"
                "\t\ttas_dev->hw_init = false;\n"
                "\t\ttas_dev->resume_playback_reinit_pending = false;\n"
                "\t}\n",
                "update_status clear pending",
            )
        return text

    if "when=update_status" in text:
        text = must_replace(
            text,
            "\t\treturn tas2783_fw_reinit(&slave->dev, slave);\n"
            "\t}\n\n"
            "\tif (status == SDW_SLAVE_ATTACHED && tas_dev->hw_init &&\n",
            "\t\treturn tas2783_post_sleep_resume_fw_reinit(&slave->dev, slave);\n"
            "\t}\n\n"
            "\tif (status == SDW_SLAVE_ATTACHED && tas_dev->hw_init &&\n",
            "update_status W2 path",
        )
        return text

    if "tas2783_post_sleep_resume_fw_reinit(&slave->dev, slave)" in text:
        return text

    return must_replace(
        text,
        "\tif (status == SDW_SLAVE_UNATTACHED)\n"
        "\t\ttas_dev->hw_init = false;\n",
        "\tif (status == SDW_SLAVE_UNATTACHED) {\n"
        "\t\ttas_dev->hw_init = false;\n"
        "\t\ttas_dev->resume_playback_reinit_pending = false;\n"
        "\t}\n\n"
        "\tif (status == SDW_SLAVE_ATTACHED && tas_dev->post_system_sleep) {\n"
        "\t\tregcache_cache_only(tas_dev->regmap, false);\n"
        "\t\tregcache_sync(tas_dev->regmap);\n"
        "\t\treturn tas2783_post_sleep_resume_fw_reinit(&slave->dev, slave);\n"
        "\t}\n",
        "update_status new hook",
    )


def main() -> int:
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <tas2783-sdw.c>", file=sys.stderr)
        return 2

    path = Path(sys.argv[1])
    text = path.read_text()

    if "resume_playback_reinit_pending" in text and "post-sleep playback fw_reinit failed" in text:
        print("upstream post-sleep hw_params reinit already present")
        return 0

    text = add_struct_field(text)
    text = add_post_sleep_helper(text)
    text = clear_pending_on_suspend(text)
    text = patch_w6_cancel(text)
    text = patch_w2_force(text)
    text = patch_resume_paths(text)
    text = patch_update_status(text)
    text = patch_hw_params(text)

    path.write_text(text)
    print(f"upstream post-sleep hw_params reinit applied to {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
