#!/usr/bin/env bash
# Genera parches upstream limpios (sin ENZOPLAY) en upstream/
set -euo pipefail

VANILLA="${VANILLA:-/usr/src/linux-source-7.0.0}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO/upstream"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

die() { echo "ERROR: $*" >&2; exit 1; }
[[ -f "$VANILLA/sound/soc/codecs/tas2783-sdw.c" ]] || die "VANILLA no encontrado: $VANILLA"

mkpatch() {
	local out="$1" old="$2" new="$3" relpath="$4"
	mkdir -p "$(dirname "$out")"
	diff -u --label "a/$relpath" --label "b/$relpath" "$old" "$new" > "$out" || [[ $? -eq 1 ]]
}

cp "$VANILLA/sound/soc/codecs/tas2783-sdw.c" "$TMP/tas2783-sdw.c"
cp "$VANILLA/sound/soc/sdw_utils/soc_sdw_utils.c" "$TMP/soc_sdw_utils.c"

# --- Serie 1: capture sin source_ports ---
S1="$TMP/s1.c"
cp "$TMP/tas2783-sdw.c" "$S1"
python3 - "$S1" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
needle = "\tif (!sdw_stream)\n\t\treturn -EINVAL;\n\n\tret = tas_clear_latch"
insert = """\tif (!sdw_stream)
\t\treturn -EINVAL;

\t/*
\t * Speaker-only DisCo exposes sink_ports (playback) but no source_ports.
\t * Do not join the capture SDW stream or sdw_program_port_params()
\t * will fail with -EINVAL on a non-existent DPN.
\t */
\tif (substream->stream == SNDRV_PCM_STREAM_CAPTURE &&
\t    !sdw_peripheral->prop.source_ports) {
\t\tdev_dbg(tas_dev->dev,
\t\t\t"no source_ports, skipping capture hw_params\\n");
\t\treturn 0;
\t}

\tret = tas_clear_latch"""
if needle not in text:
    sys.exit("serie1: anchor hw_params not found")
text = text.replace(needle, insert, 1)
needle2 = "\tstruct sdw_stream_runtime *sdw_stream =\n\t\tsnd_soc_dai_get_dma_data(dai, substream);\n\n\tsdw_stream_remove_slave"
insert2 = """\tstruct sdw_stream_runtime *sdw_stream =
\t\tsnd_soc_dai_get_dma_data(dai, substream);

\tif (substream->stream == SNDRV_PCM_STREAM_CAPTURE &&
\t    !tas_dev->sdw_peripheral->prop.source_ports)
\t\treturn 0;

\tsdw_stream_remove_slave"""
if needle2 not in text:
    sys.exit("serie1: anchor hw_free not found")
text = text.replace(needle2, insert2, 1)
open(path, "w").write(text)
PY
mkpatch "$OUT/series-1-capture/0001-tas2783-skip-capture-without-source-ports.patch" \
	"$TMP/tas2783-sdw.c" "$S1" "sound/soc/codecs/tas2783-sdw.c"

# --- Serie 2: firmware ---
S2A="$TMP/s2a.c"
cp "$TMP/tas2783-sdw.c" "$S2A"
python3 - "$S2A" <<'PY'
import sys, re
path = sys.argv[1]
text = open(path).read()
text = text.replace(
    "#define FW_FL_HDR\t20 /* minimum number of bytes in one chunk */\n",
    "#define FW_FL_HDR\t20 /* minimum number of bytes in one chunk */\n"
    "#define TAS2783_FW_NWRITE_RETRIES\t5\n",
    1)
old = """\t\tret = sdw_nwrite_no_pm(tas_dev->sdw_peripheral,
\t\t\t\t       file->dest_addr,
\t\t\t\t       file->length,
\t\t\t\t       file->fw_data);
\t\tif (ret < 0) {"""
new = """\t\t{
\t\t\tint attempt;

\t\t\tret = -EIO;
\t\t\tfor (attempt = 0; attempt < TAS2783_FW_NWRITE_RETRIES; attempt++) {
\t\t\t\tret = sdw_nwrite_no_pm(tas_dev->sdw_peripheral,
\t\t\t\t\t\t       file->dest_addr,
\t\t\t\t\t\t       file->length,
\t\t\t\t\t\t       file->fw_data);
\t\t\t\tif (ret >= 0)
\t\t\t\t\tbreak;
\t\t\t\tif (ret != -ETIMEDOUT && ret != -EAGAIN)
\t\t\t\t\tbreak;
\t\t\t\tif (attempt + 1 < TAS2783_FW_NWRITE_RETRIES)
\t\t\t\t\tusleep_range(10000, 15000);
\t\t\t}
\t\t}
\t\tif (ret < 0) {"""
if old not in text:
    sys.exit("serie2a: nwrite block not found")
text = text.replace(old, new, 1)
open(path, "w").write(text)
PY
mkpatch "$OUT/series-2-firmware/0001-tas2783-fw-retry-nwrite-on-timeout.patch" \
	"$TMP/tas2783-sdw.c" "$S2A" "sound/soc/codecs/tas2783-sdw.c"

S2B="$TMP/s2b.c"
cp "$S2A" "$S2B"
python3 - "$S2B" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
old = """\tif (!tas_dev->fw_dl_success) {
\t\tdev_err(tas_dev->dev, "error playback without fw download");
\t\treturn -EINVAL;
\t}"""
new = """\tif (!tas_dev->fw_dl_success && !tas_dev->fw_dl_task_done) {
\t\tret = wait_event_timeout(tas_dev->fw_wait, tas_dev->fw_dl_task_done,
\t\t\t\t\t msecs_to_jiffies(TIMEOUT_FW_DL_MS));
\t\tif (!ret)
\t\t\tdev_err(tas_dev->dev, "fw download wait timeout in hw_params");
\t}

\tif (!tas_dev->fw_dl_success) {
\t\tdev_err(tas_dev->dev, "error playback without fw download");
\t\treturn -EINVAL;
\t}"""
if old not in text:
    sys.exit("serie2b: fw check not found")
text = text.replace(old, new, 1)
open(path, "w").write(text)
PY
mkpatch "$OUT/series-2-firmware/0002-tas2783-hw-params-wait-for-fw-download.patch" \
	"$S2A" "$S2B" "sound/soc/codecs/tas2783-sdw.c"

# --- Serie 3: channel map ---
S3A="$TMP/s3a.c"
cp "$TMP/soc_sdw_utils.c" "$S3A"
python3 - "$S3A" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
old = """\t/* Identical data will be sent to all codecs in playback */
\tif (substream->stream == SNDRV_PCM_STREAM_PLAYBACK) {
\t\tch_mask = GENMASK(ch - 1, 0);
\t\tstep = 0;
\t} else {"""
new = """\t/* Identical data will be sent to all codecs in playback */
\tif (substream->stream == SNDRV_PCM_STREAM_PLAYBACK) {
\t\tnum_codecs = rtd->dai_link->num_codecs;
\t\tif (num_codecs > 1 && ch == num_codecs) {
\t\t\tfor_each_link_ch_maps(rtd->dai_link, i, ch_maps)
\t\t\t\tch_maps->ch_mask = BIT(i);
\t\t\treturn 0;
\t\t}
\t\tch_mask = GENMASK(ch - 1, 0);
\t\tstep = 0;
\t} else {"""
if old not in text:
    sys.exit("serie3a: hw_params playback block not found")
text = text.replace(old, new, 1)
open(path, "w").write(text)
PY
mkpatch "$OUT/series-3-channel-map/0001-sdw-utils-assign-playback-ch-map-per-codec.patch" \
	"$TMP/soc_sdw_utils.c" "$S3A" "sound/soc/sdw_utils/soc_sdw_utils.c"

S3B="$TMP/s3b.c"
cp "$TMP/tas2783-sdw.c" "$S3B"
python3 - "$S3B" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
old = """\t/* port 1 for playback */
\tif (substream->stream == SNDRV_PCM_STREAM_PLAYBACK)
\t\tport_config.num = 1;
\telse
\t\tport_config.num = 2;

\tret = sdw_stream_add_slave(sdw_peripheral,"""
new = """\t/* port 1 for playback */
\tif (substream->stream == SNDRV_PCM_STREAM_PLAYBACK)
\t\tport_config.num = 1;
\telse
\t\tport_config.num = 2;

\t{
\t\tstruct snd_soc_pcm_runtime *rtd = snd_soc_substream_to_rtd(substream);
\t\tconst struct snd_soc_dai_link_ch_map *ch_map;

\t\tfor_each_rtd_ch_maps(rtd, i, ch_map) {
\t\t\tif (snd_soc_rtd_to_codec(rtd, ch_map->codec) == dai &&
\t\t\t    ch_map->ch_mask) {
\t\t\t\tport_config.ch_mask = ch_map->ch_mask;
\t\t\t\tbreak;
\t\t\t}
\t\t}
\t}

\tret = sdw_stream_add_slave(sdw_peripheral,"""
if old not in text:
    sys.exit("serie3b: port_config block not found")
text = text.replace(old, new, 1)
open(path, "w").write(text)
PY
mkpatch "$OUT/series-3-channel-map/0002-tas2783-honor-dai-link-channel-map.patch" \
	"$TMP/tas2783-sdw.c" "$S3B" "sound/soc/codecs/tas2783-sdw.c"

echo "OK: diffs crudos (usar series-A/B/C para git send-email)"
