#!/usr/bin/env python3
"""Apply upstream candidate: one-shot fw_reinit on first hw_params after system sleep."""
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

    if "resume_playback_reinit_pending" in text:
        print("upstream post-sleep hw_params reinit already present")
        return 0

    text = must_replace(
        text,
        "\tbool fw_dl_success;\n};\n",
        "\tbool fw_dl_success;\n"
        "\tbool post_system_sleep;\n"
        "\tbool resume_playback_reinit_pending;\n"
        "};\n",
        "struct fields",
    )

    text = must_replace(
        text,
        "static s32 tas2783_fw_reinit(struct device *dev, struct sdw_slave *slave);\n",
        "static s32 tas2783_fw_reinit(struct device *dev, struct sdw_slave *slave);\n\n"
        "static s32 tas2783_post_sleep_resume_fw_reinit(struct device *dev,\n"
        "\t\t\t\t\t\t       struct sdw_slave *slave)\n"
        "{\n"
        "\tstruct tas2783_prv *tas_dev = dev_get_drvdata(dev);\n"
        "\ts32 ret;\n\n"
        "\tif (!tas_dev)\n"
        "\t\treturn -ENODEV;\n\n"
        "\ttas_dev->post_system_sleep = false;\n"
        "\tret = tas2783_fw_reinit(dev, slave);\n"
        "\tif (!ret)\n"
        "\t\ttas_dev->resume_playback_reinit_pending = true;\n\n"
        "\treturn ret;\n"
        "}\n",
        "post_sleep helper",
    )

    # system_suspend — accept W2 or vanilla hw_init guard
    if "post_system_sleep = true" in text:
        text = must_replace(
            text,
            "\t\ttas_dev->post_system_sleep = true;\n",
            "\t\ttas_dev->post_system_sleep = true;\n"
            "\t\ttas_dev->resume_playback_reinit_pending = false;\n",
            "suspend clear pending",
        )
    else:
        text = must_replace(
            text,
            "\tif (tas_dev && tas_dev->hw_init) {\n"
            "\t\ttas_dev->hw_init = false;\n",
            "\tif (tas_dev) {\n"
            "\t\ttas_dev->post_system_sleep = true;\n"
            "\t\ttas_dev->resume_playback_reinit_pending = false;\n"
            "\t\ttas_dev->hw_init = false;\n",
            "suspend post_system_sleep",
        )

    # resume path
    old_resume_w2 = (
        "\tif (tas_dev->post_system_sleep &&\n"
        "\t    tas_dev->status == SDW_SLAVE_ATTACHED) {\n"
    )
    if old_resume_w2 in text and "tas2783_post_sleep_resume_fw_reinit" not in text:
        # Replace W2 debug block if present
        for block in (
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
        ):
            if block[0] in text:
                text = text.replace(block[0], block[1], 1)
                break
        else:
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

    # update_status
    if "when=update_status" in text:
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
            "\t\treturn tas2783_post_sleep_resume_fw_reinit(&slave->dev, slave);\n"
            "\t}\n",
            "update_status W4 path",
        )
    elif "when=update_status uid" in text:
        text = must_replace(
            text,
            "\tif (status == SDW_SLAVE_ATTACHED && tas_dev->post_system_sleep) {\n"
            "\t\tdev_info(dev,\n"
            "\t\t\t \"W2 ctx=tas fn=force_fw_reinit when=update_status uid=%d\\n\",\n"
            "\t\t\t tas_dev->sdw_peripheral->id.unique_id);\n"
            "\t\ttas_dev->post_system_sleep = false;\n"
            "\t\tregcache_cache_only(tas_dev->regmap, false);\n"
            "\t\tregcache_sync(tas_dev->regmap);\n"
            "\t\treturn tas2783_fw_reinit(&slave->dev, slave);\n"
            "\t}\n",
            "\tif (status == SDW_SLAVE_ATTACHED && tas_dev->post_system_sleep) {\n"
            "\t\tregcache_cache_only(tas_dev->regmap, false);\n"
            "\t\tregcache_sync(tas_dev->regmap);\n"
            "\t\treturn tas2783_post_sleep_resume_fw_reinit(&slave->dev, slave);\n"
            "\t}\n",
            "update_status W2 path",
        )
    else:
        text = must_replace(
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

    text = must_replace(
        text,
        "\tstruct sdw_slave *sdw_peripheral = tas_dev->sdw_peripheral;\n"
        "\ts32 ret, retry = 3;\n\n"
        "\tif (!tas_dev->fw_dl_success && !tas_dev->fw_dl_task_done &&\n",
        "\tstruct sdw_slave *sdw_peripheral = tas_dev->sdw_peripheral;\n"
        "\ts32 ret, retry = 3;\n\n"
        "\tif (tas_dev->resume_playback_reinit_pending &&\n"
        "\t    tas_dev->status == SDW_SLAVE_ATTACHED) {\n"
        "\t\ttas_dev->resume_playback_reinit_pending = false;\n"
        "\t\tret = tas2783_fw_reinit(&sdw_peripheral->dev, sdw_peripheral);\n"
        "\t\tif (ret) {\n"
        "\t\t\tdev_warn(tas_dev->dev,\n"
        "\t\t\t\t \"post-sleep playback fw_reinit failed: %d\\n\", ret);\n"
        "\t\t\treturn ret;\n"
        "\t\t}\n"
        "\t}\n\n"
        "\tif (!tas_dev->fw_dl_success && !tas_dev->fw_dl_task_done &&\n",
        "hw_params one-shot reinit",
    )

    path.write_text(text)
    print(f"upstream post-sleep hw_params reinit applied to {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
