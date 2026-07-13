#!/usr/bin/env python3
"""Fix W4b ordering bugs in tas2783-sdw.c (forward decls + init_seq placement)."""
from __future__ import annotations

import sys
from pathlib import Path

INIT_SEQ_FN = """
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

FORWARD_DECLS = (
    "static u8 tas2783_w4_uid(struct tas2783_prv *tas_dev);\n"
    "static void tas2783_w5_dbg_init(struct tas2783_prv *tas_dev);\n"
    "static s32 tas2783_w4b_init_seq(struct tas2783_prv *tas_dev, const char *caller);\n"
)

EARLY_INIT_SEQ = """
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


def main() -> int:
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <tas2783-sdw.c>", file=sys.stderr)
        return 2

    path = Path(sys.argv[1])
    text = path.read_text()

    if "W4b ctx=write" not in text:
        print("W4b not present — nothing to repair", file=sys.stderr)
        return 1

    changed = False

    anchor = "static s32 tas2783_fw_reinit(struct device *dev, struct sdw_slave *slave);\n\n"
    if "static u8 tas2783_w4_uid(struct tas2783_prv *tas_dev);\n" not in text:
        text = text.replace(anchor, anchor + FORWARD_DECLS + "\n", 1)
        changed = True
        print("Added forward declarations")

    if EARLY_INIT_SEQ.strip() in text:
        text = text.replace(EARLY_INIT_SEQ, "", 1)
        changed = True
        print("Removed early tas2783_w4b_init_seq (before init_seq array)")

    marker = "\tREG_SEQ0(0x008000c4, 0x00),\n};\n\nstatic int tas2783_sdca_mbq_size"
    insert_marker = "\tREG_SEQ0(0x008000c4, 0x00),\n};\n\n"
    if "static s32 tas2783_w4b_init_seq(struct tas2783_prv *tas_dev, const char *caller)\n{\n\ts32 ret = 0;\n\tint i;\n\n\tfor (i = 0; i < ARRAY_SIZE(tas2783_init_seq)" not in text:
        if insert_marker + "static int tas2783_sdca_mbq_size" in text:
            text = text.replace(
                insert_marker + "static int tas2783_sdca_mbq_size",
                insert_marker + INIT_SEQ_FN + "\nstatic int tas2783_sdca_mbq_size",
                1,
            )
            changed = True
            print("Inserted tas2783_w4b_init_seq after tas2783_init_seq[]")

    if not changed:
        print("Already repaired")
        return 0

    path.write_text(text)
    print(f"OK: repaired {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
