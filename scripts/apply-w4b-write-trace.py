#!/usr/bin/env python3
"""Apply W4b phased write trace + W5 manual reinit on tas2783-sdw.c (requires W4)."""
from __future__ import annotations

import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <tas2783-sdw.c>", file=sys.stderr)
        return 2

    path = Path(sys.argv[1])
    text = path.read_text()
    if "W4 ctx=life seq=" not in text:
        print("ERROR: W4 trace not present — apply W4 first", file=sys.stderr)
        return 1
    if "W4b ctx=write" in text:
        print("W4b already present")
        return 0

    text = text.replace(
        'MODULE_PARM_DESC(w4_readback_trace,\n\t\t "Read back PDE23/PPU21/FU mute/AMP after key milestones");\n',
        'MODULE_PARM_DESC(w4_readback_trace,\n\t\t "Read back PDE23/PPU21/FU mute/AMP after key milestones");\n\n'
        'static bool w4b_write_trace = true;\n'
        'module_param(w4b_write_trace, bool, 0644);\n'
        'MODULE_PARM_DESC(w4b_write_trace,\n'
        '\t\t "W4b: log every chip write with phase+fn (PASS vs FAIL write diff)");\n',
        1,
    )

    text = text.replace(
        "\tbool post_system_sleep;\n};\n",
        "\tbool post_system_sleep;\n\tconst char *w4b_phase;\n};\n",
        1,
    )

    if "#include <linux/debugfs.h>" not in text:
        text = text.replace(
            "#include <linux/atomic.h>\n",
            "#include <linux/atomic.h>\n#include <linux/debugfs.h>\n",
            1,
        )

    helpers = r'''
static atomic_t w4b_write_seq = ATOMIC_INIT(0);

#define W4B_PHASE_SET(tas_dev, phase) \
	do { if (tas_dev) (tas_dev)->w4b_phase = (phase); } while (0)

static void tas2783_w4b_log_write(struct tas2783_prv *tas_dev, u32 reg, u32 val,
				  s32 ret, const char *caller, const char *kind)
{
	if (!w4b_write_trace || !tas_dev || !tas_dev->dev)
		return;
	dev_info(tas_dev->dev,
		 "W4b ctx=write seq=%d uid=%d phase=%s fn=%s kind=%s reg=0x%08x val=0x%x ret=%d\n",
		 atomic_inc_return(&w4b_write_seq), tas2783_w4_uid(tas_dev),
		 tas_dev->w4b_phase ? tas_dev->w4b_phase : "?",
		 caller, kind, reg, val, ret);
}

static s32 tas2783_w4b_regmap_write(struct tas2783_prv *tas_dev, u32 reg, u32 val,
				    const char *caller)
{
	s32 ret = regmap_write(tas_dev->regmap, reg, val);

	tas2783_w4b_log_write(tas_dev, reg, val, ret, caller, "regmap");
	if (w4_sdca_trace)
		dev_info(tas_dev->dev,
			 "W4 ctx=sdca fn=regmap_write uid=%d reg=0x%08x val=0x%x ret=%d\n",
			 tas2783_w4_uid(tas_dev), reg, val, ret);
	return ret;
}

static s32 tas2783_w4b_regmap_update_bits(struct tas2783_prv *tas_dev, u32 reg,
					  u32 mask, u32 val, const char *caller)
{
	s32 ret = regmap_update_bits(tas_dev->regmap, reg, mask, val);

	tas2783_w4b_log_write(tas_dev, reg, val, ret, caller, "update_bits");
	return ret;
}

static s32 tas2783_w4b_regmap_bulk_write(struct tas2783_prv *tas_dev, u32 reg,
					 const void *buf, size_t len, const char *caller)
{
	s32 ret = regmap_bulk_write(tas_dev->regmap, reg, buf, len);
	u32 v = 0;

	if (len >= 4 && buf)
		v = get_unaligned_le32(buf);
	tas2783_w4b_log_write(tas_dev, reg, v, ret, caller, "bulk");
	return ret;
}

static s32 tas2783_w4b_sdw_write(struct tas2783_prv *tas_dev, u32 addr, u8 val,
				 const char *caller)
{
	s32 ret;

	if (!tas_dev->sdw_peripheral)
		return -ENODEV;
	ret = sdw_write_no_pm(tas_dev->sdw_peripheral, addr, val);
	tas2783_w4b_log_write(tas_dev, addr, val, ret, caller, "sdw");
	if (w4_sdca_trace)
		dev_info(tas_dev->dev,
			 "W4 ctx=sdca fn=sdw_write uid=%d addr=0x%08x val=0x%x ret=%d\n",
			 tas2783_w4_uid(tas_dev), addr, val, ret);
	return ret;
}

static void tas2783_w4b_nwrite(struct tas2783_prv *tas_dev, u32 addr, u32 len,
			       s32 ret, const char *caller)
{
	if (!w4b_write_trace)
		return;
	dev_info(tas_dev->dev,
		 "W4b ctx=write seq=%d uid=%d phase=%s fn=%s kind=nwrite reg=0x%08x val=0x%x ret=%d\n",
		 atomic_inc_return(&w4b_write_seq), tas2783_w4_uid(tas_dev),
		 tas_dev->w4b_phase ? tas_dev->w4b_phase : "?",
		 caller, addr, len, ret);
}

'''

    text = text.replace(
        "static s32 tas2783_fw_reinit(struct device *dev, struct sdw_slave *slave);\n\n",
        "static s32 tas2783_fw_reinit(struct device *dev, struct sdw_slave *slave);\n"
        "static u8 tas2783_w4_uid(struct tas2783_prv *tas_dev);\n"
        "static void tas2783_w5_dbg_init(struct tas2783_prv *tas_dev);\n"
        "static s32 tas2783_w4b_init_seq(struct tas2783_prv *tas_dev, const char *caller);\n\n",
        1,
    )

    text = text.replace(
        "static atomic_t w4_seq = ATOMIC_INIT(0);\n\nstatic u8 tas2783_w4_uid",
        "static atomic_t w4_seq = ATOMIC_INIT(0);\n" + helpers + "\nstatic u8 tas2783_w4_uid",
        1,
    )

    text = text.replace(
        "static s32 tas2783_w4_regmap_write(struct tas2783_prv *tas_dev, u32 reg, u32 val)\n"
        "{\n\ts32 ret = regmap_write(tas_dev->regmap, reg, val);\n\n\tif (w4_sdca_trace)\n"
        "\t\tdev_info(tas_dev->dev,\n"
        '\t\t\t "W4 ctx=sdca fn=regmap_write uid=%d reg=0x%08x val=0x%x ret=%d\\n",\n'
        "\t\t\t tas2783_w4_uid(tas_dev), reg, val, ret);\n\treturn ret;\n}\n\n"
        "static s32 tas2783_w4_sdw_write",
        "static s32 tas2783_w4_regmap_write(struct tas2783_prv *tas_dev, u32 reg, u32 val)\n"
        "{\n\treturn tas2783_w4b_regmap_write(tas_dev, reg, val, __func__);\n}\n\n"
        "static s32 tas2783_w4_sdw_write",
        1,
    )

    text = text.replace(
        "static s32 tas2783_w4_sdw_write(struct tas2783_prv *tas_dev, u32 addr, u8 val)\n"
        "{\n\ts32 ret;\n\n\tif (!tas_dev->sdw_peripheral)\n\t\treturn -ENODEV;\n"
        "\tret = sdw_write_no_pm(tas_dev->sdw_peripheral, addr, val);\n\tif (w4_sdca_trace)\n"
        "\t\tdev_info(tas_dev->dev,\n"
        '\t\t\t "W4 ctx=sdca fn=sdw_write uid=%d addr=0x%08x val=0x%x ret=%d\\n",\n'
        "\t\t\t tas2783_w4_uid(tas_dev), addr, val, ret);\n\treturn ret;\n}",
        "static s32 tas2783_w4_sdw_write(struct tas2783_prv *tas_dev, u32 addr, u8 val)\n"
        "{\n\treturn tas2783_w4b_sdw_write(tas_dev, addr, val, __func__);\n}",
        1,
    )

    replacements = [
        (
            "\t\t\tregmap_bulk_write(tas_dev->regmap, tas2783_cali_reg[i],\n"
            "\t\t\t\t\t  buf, sizeof(u32));",
            "\t\t\ttas2783_w4b_regmap_bulk_write(tas_dev, tas2783_cali_reg[i],\n"
            "\t\t\t\t\t\t\t      buf, sizeof(u32),\n"
            "\t\t\t\t\t\t\t      __func__);",
        ),
        (
            "\t\t\t\tif (w4_sdca_trace)\n\t\t\t\t\tdev_info(tas_dev->dev,\n"
            '\t\t\t\t\t\t "W4 ctx=sdca fn=nwrite uid=%d addr=0x%x len=%d try=%d ret=%d file=%d\\n",\n'
            "\t\t\t\t\t\t uid, file->dest_addr, file->length,\n"
            "\t\t\t\t\t\t attempt, ret, cur_file);",
            "\t\t\t\ttas2783_w4b_nwrite(tas_dev, file->dest_addr, file->length,\n"
            "\t\t\t\t\t\t   ret, __func__);",
        ),
        (
            "static inline s32 tas_clear_latch(struct tas2783_prv *priv)\n{\n"
            "\treturn regmap_update_bits(priv->regmap,\n"
            "\t\t\t\t  TASDEV_REG_SDW(0, 0, 0x5c),\n"
            "\t\t\t\t  0x04, 0x04);\n}",
            "static inline s32 tas_clear_latch(struct tas2783_prv *priv)\n{\n"
            "\treturn tas2783_w4b_regmap_update_bits(priv, TASDEV_REG_SDW(0, 0, 0x5c),\n"
            "\t\t\t\t\t\t      0x04, 0x04, __func__);\n}",
        ),
        (
            "\tret = regmap_write(tas_dev->regmap,\n"
            "\t\t\t   SDW_SDCA_CTL(1, TAS2783_SDCA_ENT_PDE23,\n"
            "\t\t\t\t\tTAS2783_SDCA_CTL_REQ_POW_STATE, 0),\n"
            "\t\t\t   TAS2783_SDCA_POW_STATE_OFF);",
            "\tret = tas2783_w4b_regmap_write(tas_dev,\n"
            "\t\t\t   SDW_SDCA_CTL(1, TAS2783_SDCA_ENT_PDE23,\n"
            "\t\t\t\t\tTAS2783_SDCA_CTL_REQ_POW_STATE, 0),\n"
            "\t\t\t   TAS2783_SDCA_POW_STATE_OFF, __func__);",
        ),
        (
            '\t\t\ttas2783_w4_life(dev, unique_id, "io_init", "init_seq");\n'
            "\t\t\tret = regmap_multi_reg_write(tas_dev->regmap, tas2783_init_seq,\n"
            "\t\t\t\t\t\t     ARRAY_SIZE(tas2783_init_seq));",
            '\t\t\ttas2783_w4_life(dev, unique_id, "io_init", "init_seq");\n'
            '\t\t\tW4B_PHASE_SET(tas_dev, "INIT_SEQ");\n'
            "\t\t\tret = tas2783_w4b_init_seq(tas_dev, __func__);",
        ),
        (
            "\t\tret = sdw_write_no_pm(slave, addr, prep_ch->ch_mask);",
            '\t\tW4B_PHASE_SET(tas_dev, "RUNTIME");\n'
            "\t\tret = tas2783_w4b_sdw_write(tas_dev, addr, prep_ch->ch_mask, __func__);",
        ),
        (
            "\t\tret = sdw_write_no_pm(slave, addr, 0x00);",
            '\t\tW4B_PHASE_SET(tas_dev, "RUNTIME");\n'
            "\t\tret = tas2783_w4b_sdw_write(tas_dev, addr, 0x00, __func__);",
        ),
        (
            "\t(struct tas2783_prv *)context;\n\tconst u8 *buf = NULL;\n"
            "\tu8 uid = tas2783_w4_uid(tas_dev);\n\n\ttas2783_w4_life(tas_dev->dev, uid, "
            '"fw_ready", "enter");',
            "\t(struct tas2783_prv *)context;\n\tconst u8 *buf = NULL;\n"
            "\tu8 uid = tas2783_w4_uid(tas_dev);\n\n\tW4B_PHASE_SET(tas_dev, "
            '"FW_DL");\n\ttas2783_w4_life(tas_dev->dev, uid, "fw_ready", "enter");',
        ),
        (
            'static s32 tas2783_update_calibdata(struct tas2783_prv *tas_dev)\n{\n'
            '\ttas2783_w4_life(tas_dev->dev, tas2783_w4_uid(tas_dev),\n\t\t\t"update_calib", "enter");',
            'static s32 tas2783_update_calibdata(struct tas2783_prv *tas_dev)\n{\n'
            '\tW4B_PHASE_SET(tas_dev, "CALIB");\n'
            '\ttas2783_w4_life(tas_dev->dev, tas2783_w4_uid(tas_dev),\n\t\t\t"update_calib", "enter");',
        ),
        (
            "struct tas2783_prv *tas_dev = snd_soc_component_get_drvdata(component);\n\ts32 mute;\n\n"
            '\ttas2783_w4_life(tas_dev->dev, tas2783_w4_uid(tas_dev),\n\t\t\t"fu21_event",',
            "struct tas2783_prv *tas_dev = snd_soc_component_get_drvdata(component);\n\ts32 mute;\n\n"
            '\tW4B_PHASE_SET(tas_dev, "DAPM");\n'
            '\ttas2783_w4_life(tas_dev->dev, tas2783_w4_uid(tas_dev),\n\t\t\t"fu21_event",',
        ),
        (
            "struct tas2783_prv *tas_dev = snd_soc_component_get_drvdata(component);\n\ts32 mute;\n\n"
            '\ttas2783_w4_life(tas_dev->dev, tas2783_w4_uid(tas_dev),\n\t\t\t"fu23_event",',
            "struct tas2783_prv *tas_dev = snd_soc_component_get_drvdata(component);\n\ts32 mute;\n\n"
            '\tW4B_PHASE_SET(tas_dev, "DAPM");\n'
            '\ttas2783_w4_life(tas_dev->dev, tas2783_w4_uid(tas_dev),\n\t\t\t"fu23_event",',
        ),
        (
            '\ttas2783_w4_life(tas_dev->dev, uid, "hw_params", "enter");',
            '\tW4B_PHASE_SET(tas_dev, "RUNTIME");\n\ttas2783_w4_life(tas_dev->dev, uid, "hw_params", "enter");',
        ),
        (
            "\tif (tas_dev)\n\t\ttas2783_w4_life(dev, tas2783_w4_uid(tas_dev),\n"
            '\t\t\t\t"system_suspend", "enter");',
            "\tif (tas_dev) {\n\t\tW4B_PHASE_SET(tas_dev, \"SUSPEND\");\n"
            "\t\ttas2783_w4_life(dev, tas2783_w4_uid(tas_dev),\n"
            '\t\t\t\t"system_suspend", "enter");\n\t}',
        ),
        (
            '\ttas2783_w4_life(dev, uid, "resume", "enter");',
            '\tW4B_PHASE_SET(tas_dev, "RESUME");\n\ttas2783_w4_life(dev, uid, "resume", "enter");',
        ),
        (
            '\ttas2783_w4_life(dev, unique_id, "io_init", "enter");',
            '\tW4B_PHASE_SET(tas_dev, "BOOT");\n\ttas2783_w4_life(dev, unique_id, "io_init", "enter");',
        ),
        (
            '\ttas2783_w4_life(dev, tas2783_w4_uid(tas_dev), "fw_reinit", "enter");',
            '\tW4B_PHASE_SET(tas_dev, "RESUME");\n'
            '\ttas2783_w4_life(dev, tas2783_w4_uid(tas_dev), "fw_reinit", "enter");',
        ),
        (
            '\t\ttas2783_w4_life(dev, tas_dev->sdw_peripheral->id.unique_id, "update_status", "force_fw_reinit");',
            '\t\tW4B_PHASE_SET(tas_dev, "RESUME");\n'
            '\t\ttas2783_w4_life(dev, tas_dev->sdw_peripheral->id.unique_id, "update_status", "force_fw_reinit");',
        ),
        (
            '\t\t\ttas2783_w4_life(dev, unique_id, "io_init",\n\t\t\t\t\t"sdca_regmap_write_init");\n'
            "\t\t\tret = sdca_regmap_write_init(dev, tas_dev->regmap,\n"
            "\t\t\t\t\t\t     tas_dev->sa_func_data);",
            '\t\t\ttas2783_w4_life(dev, unique_id, "io_init",\n\t\t\t\t\t"sdca_regmap_write_init");\n'
            '\t\t\tW4B_PHASE_SET(tas_dev, "INIT_SEQ");\n'
            "\t\t\tret = sdca_regmap_write_init(dev, tas_dev->regmap,\n"
            "\t\t\t\t\t\t     tas_dev->sa_func_data);\n"
            "\t\t\tif (w4b_write_trace)\n"
            '\t\t\t\tdev_info(dev, "W4b ctx=meta uid=%d phase=INIT_SEQ fn=%s kind=sdca_regmap_init ret=%d\\n",\n'
            "\t\t\t\t\t unique_id, __func__, ret);",
        ),
    ]

    for old, new in replacements:
        if old not in text:
            print(f"WARN: pattern missing: {old[:60]}...", file=sys.stderr)
        else:
            text = text.replace(old, new, 1)

    w5 = r'''
/* W5 — manual fw_reinit trigger (double-reinit experiment) */
static struct dentry *tas2783_w5_dbg;

static ssize_t tas2783_w5_reinit_write(struct file *file, const char __user *buf,
				       size_t count, loff_t *ppos)
{
	struct tas2783_prv *tas_dev = file->private_data;
	struct sdw_slave *slave = tas_dev->sdw_peripheral;
	s32 ret;
	char kbuf[8];
	long v = 1;

	if (count >= sizeof(kbuf))
		return -EINVAL;
	if (copy_from_user(kbuf, buf, count))
		return -EFAULT;
	kbuf[count] = '\0';
	if (kbuf[0] >= '0' && kbuf[0] <= '9')
		v = simple_strtol(kbuf, NULL, 10);
	if (!v)
		return count;
	W4B_PHASE_SET(tas_dev, "W5_MANUAL");
	dev_info(tas_dev->dev, "W5 ctx=manual fn=fw_reinit uid=%d trigger=1\n",
		 tas2783_w4_uid(tas_dev));
	ret = tas2783_fw_reinit(&slave->dev, slave);
	dev_info(tas_dev->dev, "W5 ctx=manual fn=fw_reinit uid=%d ret=%d\n",
		 tas2783_w4_uid(tas_dev), ret);
	return count;
}

static const struct file_operations tas2783_w5_reinit_fops = {
	.write = tas2783_w5_reinit_write,
	.open = simple_open,
	.llseek = noop_llseek,
};

static void tas2783_w5_dbg_init(struct tas2783_prv *tas_dev)
{
	char name[32];

	if (!tas2783_w5_dbg)
		tas2783_w5_dbg = debugfs_create_dir("tas2783", NULL);
	if (IS_ERR(tas2783_w5_dbg))
		tas2783_w5_dbg = NULL;
	if (!tas2783_w5_dbg)
		return;
	snprintf(name, sizeof(name), "uid%u", tas2783_w4_uid(tas_dev));
	debugfs_create_file(name, 0200, tas2783_w5_dbg, tas_dev, &tas2783_w5_reinit_fops);
}

'''

    text = text.replace(
        "\ttas_dev->regmap = regmap;\n\treturn tas_init(tas_dev);",
        "\ttas_dev->regmap = regmap;\n\ttas2783_w5_dbg_init(tas_dev);\n\treturn tas_init(tas_dev);",
        1,
    )
    text = text.replace("module_sdw_driver(tas_sdw_driver);", w5 + "\nmodule_sdw_driver(tas_sdw_driver);", 1)

    init_seq_fn = """
static s32 tas2783_w4b_init_seq(struct tas2783_prv *tas_dev, const char *caller)
{
\ts32 ret = 0;
\tint i;

\tfor (i = 0; i < ARRAY_SIZE(tas2783_init_seq); i++) {
\t\tret = tas2783_w4b_regmap_write(tas_dev, tas2783_init_seq[i].reg,
\t\t\t\t\t       tas2783_init_seq[i].def, caller);
\t\tif (ret)
\t\t\tbreak;
\t}
\treturn ret;
}
"""
    anchor = "\tREG_SEQ0(0x008000c4, 0x00),\n};\n\nstatic int tas2783_sdca_mbq_size"
    if "static s32 tas2783_w4b_init_seq(struct tas2783_prv *tas_dev, const char *caller)" not in text:
        if anchor in text:
            text = text.replace(
                anchor,
                "\tREG_SEQ0(0x008000c4, 0x00),\n};\n" + init_seq_fn + "\nstatic int tas2783_sdca_mbq_size",
                1,
            )
        else:
            print("WARN: could not insert tas2783_w4b_init_seq after init_seq array", file=sys.stderr)

    if "W4b ctx=write" not in text:
        print("ERROR: W4b apply failed", file=sys.stderr)
        return 1

    path.write_text(text)
    print("OK: W4b + W5 applied")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
