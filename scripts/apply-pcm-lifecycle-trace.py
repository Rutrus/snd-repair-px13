#!/usr/bin/env python3
"""Observation-only: log TAS2783 DAI + SDW port_prep lifecycle (Case A′′).

Marker: snd_repair pcm:
Requires 0001/0001b already applied (or at least tas_dai_ops present).
No functional change beyond adding startup/prepare/trigger ops that return 0
and printk at existing hw_params/hw_free/shutdown/port_prep.
"""
from __future__ import annotations

import sys
from pathlib import Path

MARKER = "snd_repair pcm:"

TRACE_HELPERS = r"""
/* Case A′′ observation: PCM lifecycle contrast (mute-after-0001b vs reopen). */
static void tas_pcm_trace(struct tas2783_prv *tas_dev, const char *ev, int stream)
{
	if (!tas_dev || !tas_dev->dev)
		return;
	dev_info(tas_dev->dev, "snd_repair pcm: %s stream=%d attached=%d fw=%d\n",
		 ev, stream,
		 tas_dev->status == SDW_SLAVE_ATTACHED,
		 tas_dev->fw_dl_success);
}

static int tas_sdw_startup(struct snd_pcm_substream *substream,
			   struct snd_soc_dai *dai)
{
	struct tas2783_prv *tas_dev =
		snd_soc_component_get_drvdata(dai->component);

	tas_pcm_trace(tas_dev, "startup", substream->stream);
	return 0;
}

static int tas_sdw_prepare(struct snd_pcm_substream *substream,
			   struct snd_soc_dai *dai)
{
	struct tas2783_prv *tas_dev =
		snd_soc_component_get_drvdata(dai->component);

	tas_pcm_trace(tas_dev, "prepare", substream->stream);
	return 0;
}

static int tas_sdw_trigger(struct snd_pcm_substream *substream, int cmd,
			   struct snd_soc_dai *dai)
{
	struct tas2783_prv *tas_dev =
		snd_soc_component_get_drvdata(dai->component);
	const char *name = "OTHER";

	switch (cmd) {
	case SNDRV_PCM_TRIGGER_START:
		name = "trigger_START";
		break;
	case SNDRV_PCM_TRIGGER_STOP:
		name = "trigger_STOP";
		break;
	case SNDRV_PCM_TRIGGER_PAUSE_PUSH:
		name = "trigger_PAUSE_PUSH";
		break;
	case SNDRV_PCM_TRIGGER_PAUSE_RELEASE:
		name = "trigger_PAUSE_RELEASE";
		break;
	case SNDRV_PCM_TRIGGER_SUSPEND:
		name = "trigger_SUSPEND";
		break;
	case SNDRV_PCM_TRIGGER_RESUME:
		name = "trigger_RESUME";
		break;
	}
	tas_pcm_trace(tas_dev, name, substream->stream);
	return 0;
}

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

    if MARKER in text and "tas_sdw_prepare" in text:
        print("PCM lifecycle trace already present")
        return 0

    if "static const struct snd_soc_dai_ops tas_dai_ops" not in text:
        raise SystemExit("ERROR: tas_dai_ops not found")

    # Insert helpers before shutdown (first PCM ops block)
    if "tas_pcm_trace" not in text:
        text = must_replace(
            text,
            "static void tas_sdw_shutdown(struct snd_pcm_substream *substream,\n",
            TRACE_HELPERS
            + "static void tas_sdw_shutdown(struct snd_pcm_substream *substream,\n",
            "insert trace helpers",
        )

    # shutdown
    text = must_replace(
        text,
        "static void tas_sdw_shutdown(struct snd_pcm_substream *substream,\n"
        "			     struct snd_soc_dai *dai)\n"
        "{\n"
        "	snd_soc_dai_set_dma_data(dai, substream, NULL);\n"
        "}\n",
        "static void tas_sdw_shutdown(struct snd_pcm_substream *substream,\n"
        "			     struct snd_soc_dai *dai)\n"
        "{\n"
        "	struct tas2783_prv *tas_dev =\n"
        "		snd_soc_component_get_drvdata(dai->component);\n"
        "\n"
        "	tas_pcm_trace(tas_dev, \"shutdown\", substream->stream);\n"
        "	snd_soc_dai_set_dma_data(dai, substream, NULL);\n"
        "}\n",
        "shutdown trace",
    )

    # hw_params entry — after tas_dev locals / first usable point
    if 'tas_pcm_trace(tas_dev, "hw_params"' not in text:
        # after getting sdw_peripheral line
        anchor = (
            "\tstruct sdw_slave *sdw_peripheral = tas_dev->sdw_peripheral;\n"
            "\ts32 ret, retry = 3;\n"
        )
        text = must_replace(
            text,
            anchor,
            anchor
            + "\n"
            + '\ttas_pcm_trace(tas_dev, "hw_params", substream->stream);\n',
            "hw_params entry",
        )

    # hw_free entry
    if 'tas_pcm_trace(tas_dev, "hw_free"' not in text:
        text = must_replace(
            text,
            "static s32 tas_sdw_pcm_hw_free(struct snd_pcm_substream *substream,\n"
            "			       struct snd_soc_dai *dai)\n"
            "{\n"
            "	s32 ret;\n"
            "	struct snd_soc_component *component = dai->component;\n"
            "	struct tas2783_prv *tas_dev =\n"
            "		snd_soc_component_get_drvdata(component);\n",
            "static s32 tas_sdw_pcm_hw_free(struct snd_pcm_substream *substream,\n"
            "			       struct snd_soc_dai *dai)\n"
            "{\n"
            "	s32 ret;\n"
            "	struct snd_soc_component *component = dai->component;\n"
            "	struct tas2783_prv *tas_dev =\n"
            "		snd_soc_component_get_drvdata(component);\n"
            "\n"
            '\ttas_pcm_trace(tas_dev, "hw_free", substream->stream);\n',
            "hw_free entry",
        )

    # dai_ops table
    old_ops = (
        "static const struct snd_soc_dai_ops tas_dai_ops = {\n"
        "	.hw_params	= tas_sdw_hw_params,\n"
        "	.hw_free	= tas_sdw_pcm_hw_free,\n"
        "	.set_stream	= tas_set_sdw_stream,\n"
        "	.shutdown	= tas_sdw_shutdown,\n"
        "};\n"
    )
    new_ops = (
        "static const struct snd_soc_dai_ops tas_dai_ops = {\n"
        "	.startup	= tas_sdw_startup,\n"
        "	.hw_params	= tas_sdw_hw_params,\n"
        "	.hw_free	= tas_sdw_pcm_hw_free,\n"
        "	.prepare	= tas_sdw_prepare,\n"
        "	.trigger	= tas_sdw_trigger,\n"
        "	.set_stream	= tas_set_sdw_stream,\n"
        "	.shutdown	= tas_sdw_shutdown,\n"
        "};\n"
    )
    if ".prepare\t= tas_sdw_prepare" not in text:
        text = must_replace(text, old_ops, new_ops, "dai_ops")

    # port_prep
    if "snd_repair pcm: port_prep" not in text:
        text = must_replace(
            text,
            "\tdpn_prop = slave->prop.sink_dpn_prop;\n"
            "\tif (!dpn_prop || !dpn_prop->simple_ch_prep_sm)\n"
            "\t\treturn 0;\n",
            "\tdev_info(dev,\n"
            '\t\t "snd_repair pcm: port_prep port=%d ops=%d\\n",\n'
            "\t\t prep_ch->num, pre_ops);\n"
            "\tdpn_prop = slave->prop.sink_dpn_prop;\n"
            "\tif (!dpn_prop || !dpn_prop->simple_ch_prep_sm)\n"
            "\t\treturn 0;\n",
            "port_prep trace",
        )

    path.write_text(text)
    print(f"PCM lifecycle trace applied to {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
