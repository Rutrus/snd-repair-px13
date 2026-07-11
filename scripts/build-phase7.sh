#!/usr/bin/env bash
# Build/install Phase 7 AMD SoundWire experiment on Phase 6 trace base.
#
# Usage:
#   ./scripts/build-phase7.sh --experiment delay-after-d0
#   ./scripts/build-phase7.sh --experiment delay-after-d0 --delay 20
#   PHASE7_EXPERIMENT=delay-after-d0 PHASE7_DELAY_MS=20 ./scripts/build-phase7.sh
#
# Phase 6 observation patches (0003–0007) are applied first, then ONE Phase 7 patch.
# Persist phase7_delay_ms across reboot via modprobe.d (see phase7-sweep-pre.sh).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

SRC="$KERNEL_SRC"
EXPERIMENT="${PHASE7_EXPERIMENT:-}"
DELAY_MS="${PHASE7_DELAY_MS:-}"
STAMP_P7="$SRC/.snd-repair-phase7-experiment"

usage() {
	cat <<EOF
Usage:
  $0 --experiment NAME [--delay MS]

Experiments:
  delay-after-d0   module param phase7_delay_ms (0=control; archived 0005)
  stat-decode              INTR decode post-D0 + optional post_delay (0006b / 0006b.1)
  validate-manager-mask    0006b + manual schedule_work if STAT&mask (0006a)
  irq-delivery-trace       pci-ps IRQ path observation (0007.1–0007.4)
  irq-stat-correlate       0006b + 0007 + correlate (t_ms, cntl_write, /proc/interrupts)

Environment:
  PHASE7_EXPERIMENT   same as --experiment
  PHASE7_DELAY_MS     suggested value (written to state file; set on module before suspend)

After install and reboot, use modprobe.d for sweep (echo does NOT persist):

  ./scripts/phase7-sweep-pre.sh MS    # before reboot
  ./scripts/phase7-sweep-post.sh      # after login

Same-boot ad-hoc (no reboot): echo MS | sudo tee /sys/module/soundwire_amd/parameters/phase7_delay_ms
EOF
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	--experiment) EXPERIMENT="${2:?}"; shift 2 ;;
	--delay) DELAY_MS="${2:?}"; shift 2 ;;
	-h|--help) usage; exit 0 ;;
	*) echo "Unknown: $1" >&2; usage; exit 1 ;;
	esac
done

[[ -n "$EXPERIMENT" ]] || { usage; exit 1; }

phase7_patch_for() {
	case "$1" in
	delay-after-d0)
		echo "$REPO_ROOT/research/phase-7/proposed/0005-delay-after-d0.patch"
		;;
	stat-decode)
		echo "$REPO_ROOT/research/phase-7/proposed/0006b-stat-decode.patch"
		;;
	validate-manager-mask)
		echo "$REPO_ROOT/research/phase-7/proposed/0006a-validate-manager-mask.patch"
		;;
	irq-delivery-trace)
		echo "$REPO_ROOT/research/phase-7/proposed/0007-irq-delivery-trace.patch"
		;;
	irq-stat-correlate)
		echo "$REPO_ROOT/research/phase-7/proposed/0007-correlate.patch"
		;;
	*)
		echo "Unknown experiment: $1" >&2
		exit 1
		;;
	esac
}

phase7_stat_decode_partial() {
	grep -q 'SND_REPAIR_INTR_DECODE_INSTANCES' "$SRC/drivers/soundwire/amd_manager.c" 2>/dev/null &&
		grep -q 'snd_repair_phase7_intr_decode' "$SRC/drivers/soundwire/amd_manager.c" 2>/dev/null &&
		! grep -q 'snd_repair_phase7_intr_decode(dev' "$SRC/drivers/soundwire/amd_manager.c" 2>/dev/null
}

phase7_0006b_present() {
	grep -q 'SND_REPAIR_INTR_DECODE_INSTANCES' "$SRC/drivers/soundwire/amd_manager.c" 2>/dev/null &&
		grep -q 'fn=intr_decode' "$SRC/drivers/soundwire/amd_manager.c" 2>/dev/null &&
		grep -q 'snd_repair_phase7_intr_decode(dev, amd_manager, bus, "post_D0")' \
			"$SRC/drivers/soundwire/amd_manager.c" 2>/dev/null &&
		grep -q 'snd_repair_phase7_intr_decode(dev, amd_manager, bus, "post_delay")' \
			"$SRC/drivers/soundwire/amd_manager.c" 2>/dev/null &&
		grep -q 'phase7_delay_ms' "$SRC/drivers/soundwire/amd_manager.c" 2>/dev/null
}

phase7_irq_delivery_present() {
	grep -q 'PHASE7 ctx=acp fn=irq_handler_enter' "$SRC/sound/soc/amd/ps/pci-ps.c" 2>/dev/null &&
		grep -q 'PHASE7 ctx=acp fn=pm_resume_enter' "$SRC/sound/soc/amd/ps/pci-ps.c" 2>/dev/null
}

phase7_correlate_present() {
	grep -q 'EXPORT_SYMBOL_GPL(snd_repair_phase7_t_mgr_reset_ms)' \
		"$SRC/drivers/soundwire/amd_manager.c" 2>/dev/null &&
		grep -q 'fn=cntl_write who=amd_manager' "$SRC/drivers/soundwire/amd_manager.c" 2>/dev/null &&
		grep -q 'fn=cntl1_write who=acp70_host_wake' "$SRC/sound/soc/amd/ps/ps-common.c" 2>/dev/null &&
		grep -q 't_mgr_ms=%lld' "$SRC/sound/soc/amd/ps/pci-ps.c" 2>/dev/null
}

phase7_needs_pci_ps() {
	case "$1" in irq-delivery-trace|irq-stat-correlate) return 0 ;; *) return 1 ;; esac
}

phase7_present() {
	case "$1" in
	delay-after-d0)
		grep -q 'fn=delay_after_D0' "$SRC/drivers/soundwire/amd_manager.c" 2>/dev/null
		;;
	stat-decode)
		phase7_0006b_present && \
			! grep -q 'fn=manual_irq_schedule' "$SRC/drivers/soundwire/amd_manager.c" 2>/dev/null
		;;
	validate-manager-mask)
		phase7_0006b_present &&
			grep -q 'snd_repair_phase7_try_manual_irq' "$SRC/drivers/soundwire/amd_manager.c" 2>/dev/null &&
			grep -q 'fn=manual_irq_schedule' "$SRC/drivers/soundwire/amd_manager.c" 2>/dev/null
		;;
	irq-delivery-trace)
		phase7_irq_delivery_present
		;;
	irq-stat-correlate)
		phase7_0006b_present && phase7_irq_delivery_present && phase7_correlate_present
		;;
	*) return 1 ;;
	esac
}

apply_phase7_pci_patch() {
	local patch="$1"
	local label="$2"
	rm -f "$SRC/sound/soc/amd/ps/pci-ps.c.rej"
	echo "==> Applying Phase 7 (pci-ps): $label"
	if patch -p1 --forward -d "$SRC" <"$patch"; then
		return 0
	fi
	rm -f "$SRC/sound/soc/amd/ps/pci-ps.c.rej"
	return 1
}

apply_phase7_correlate_patch() {
	local patch="$1"
	rm -f "$SRC/drivers/soundwire/amd_manager.c.rej" \
		"$SRC/sound/soc/amd/ps/pci-ps.c.rej" \
		"$SRC/sound/soc/amd/ps/ps-common.c.rej"
	echo "==> Applying Phase 7: irq-stat-correlate (0007-correlate)"
	if patch -p1 --forward -d "$SRC" <"$patch"; then
		return 0
	fi
	rm -f "$SRC/drivers/soundwire/amd_manager.c.rej" \
		"$SRC/sound/soc/amd/ps/pci-ps.c.rej" \
		"$SRC/sound/soc/amd/ps/ps-common.c.rej"
	if phase7_correlate_present; then
		echo "==> correlate markers already present (partial/re-apply) — OK"
		return 0
	fi
	return 1
}

apply_phase7_patch() {
	local patch="$1"
	local label="$2"
	rm -f "$SRC/drivers/soundwire/amd_manager.c.rej"
	echo "==> Applying Phase 7: $label"
	if patch -p1 --forward -d "$SRC" <"$patch"; then
		return 0
	fi
	rm -f "$SRC/drivers/soundwire/amd_manager.c.rej"
	return 1
}

PATCH_P7="$(phase7_patch_for "$EXPERIMENT")"
[[ -f "$PATCH_P7" ]] || { echo "Missing $PATCH_P7" >&2; exit 1; }

if [[ -f "$STAMP_P7" ]] && [[ "$(head -1 "$STAMP_P7")" != "$EXPERIMENT" ]]; then
	echo "==> Phase 7 experiment switch: $(head -1 "$STAMP_P7") → $EXPERIMENT (reset amd_manager)"
	"$SCRIPT_DIR/reset-phase6-amd-manager.sh"
	rm -f "$SRC"/.snd-repair-phase6-*
fi

echo "==> Phase 6 trace base (0003–0007)"
PHASE6_SKIP_BUILD=1 "$SCRIPT_DIR/build-phase6-amd-trace.sh"

cd "$SRC"
if phase7_present "$EXPERIMENT"; then
	echo "==> Phase 7 $EXPERIMENT already present — skip patch"
else
	case "$EXPERIMENT" in
	validate-manager-mask)
		PATCH_0006B="$REPO_ROOT/research/phase-7/proposed/0006b-stat-decode.patch"
		if ! phase7_0006b_present; then
			apply_phase7_patch "$PATCH_0006B" "stat-decode (0006b base)" || {
				phase7_0006b_present || { echo "ERROR: 0006b base failed" >&2; exit 1; }
			}
		fi
		if ! phase7_present "$EXPERIMENT"; then
			apply_phase7_patch "$PATCH_P7" "validate-manager-mask (0006a)" || {
				phase7_present "$EXPERIMENT" || {
					echo "ERROR: 0006a patch failed" >&2
					[[ -f "$SRC/drivers/soundwire/amd_manager.c.rej" ]] && \
						cat "$SRC/drivers/soundwire/amd_manager.c.rej" >&2
					exit 1
				}
			}
		fi
		;;
		stat-decode|delay-after-d0)
		if ! apply_phase7_patch "$PATCH_P7" "$EXPERIMENT"; then
			if phase7_present "$EXPERIMENT"; then
				echo "==> Phase 7 $EXPERIMENT already present — skip patch"
			elif [[ "$EXPERIMENT" == stat-decode ]] && phase7_stat_decode_partial; then
				echo "ERROR: Phase 7 0006b partially applied" >&2
				echo "  Fix: ./scripts/regenerate-phase7-0006b.sh" >&2
				exit 1
			else
				echo "ERROR: Phase 7 patch failed" >&2
				[[ -f "$SRC/drivers/soundwire/amd_manager.c.rej" ]] && \
					cat "$SRC/drivers/soundwire/amd_manager.c.rej" >&2
				exit 1
			fi
		fi
		;;
	irq-delivery-trace)
		if ! phase7_irq_delivery_present; then
			apply_phase7_pci_patch "$PATCH_P7" "irq-delivery-trace (0007)" || {
				phase7_irq_delivery_present || {
					echo "ERROR: 0007 pci-ps patch failed" >&2
					[[ -f "$SRC/sound/soc/amd/ps/pci-ps.c.rej" ]] && \
						cat "$SRC/sound/soc/amd/ps/pci-ps.c.rej" >&2
					exit 1
				}
			}
		fi
		;;
	irq-stat-correlate)
		PATCH_0006B="$REPO_ROOT/research/phase-7/proposed/0006b-stat-decode.patch"
		PATCH_0007="$REPO_ROOT/research/phase-7/proposed/0007-irq-delivery-trace.patch"
		PATCH_CORR="$REPO_ROOT/research/phase-7/proposed/0007-correlate.patch"
		if ! phase7_0006b_present; then
			apply_phase7_patch "$PATCH_0006B" "stat-decode (0006b base)" || {
				phase7_0006b_present || { echo "ERROR: 0006b base failed" >&2; exit 1; }
			}
		fi
		if ! phase7_irq_delivery_present; then
			apply_phase7_pci_patch "$PATCH_0007" "irq-delivery-trace (0007)" || {
				phase7_irq_delivery_present || {
					echo "ERROR: 0007 pci-ps patch failed" >&2
					[[ -f "$SRC/sound/soc/amd/ps/pci-ps.c.rej" ]] && \
						cat "$SRC/sound/soc/amd/ps/pci-ps.c.rej" >&2
					exit 1
				}
			}
		fi
		if ! phase7_correlate_present; then
			apply_phase7_correlate_patch "$PATCH_CORR" || {
				phase7_correlate_present || {
					echo "ERROR: 0007-correlate patch failed" >&2
					for rej in \
						"$SRC/drivers/soundwire/amd_manager.c.rej" \
						"$SRC/sound/soc/amd/ps/pci-ps.c.rej" \
						"$SRC/sound/soc/amd/ps/ps-common.c.rej"; do
						[[ -f "$rej" ]] && cat "$rej" >&2
					done
					exit 1
				}
			}
		fi
		;;
	esac
	if [[ "$EXPERIMENT" == irq-delivery-trace ]]; then
		[[ -f "$SRC/sound/soc/amd/ps/pci-ps.c.rej" ]] && {
			echo "ERROR: Phase 7 pci-ps patch left .rej" >&2
			exit 1
		}
		phase7_irq_delivery_present || {
			echo "ERROR: Phase 7 irq-delivery-trace incomplete after patch" >&2
			exit 1
		}
	elif [[ "$EXPERIMENT" == irq-stat-correlate ]]; then
		for rej in \
			"$SRC/drivers/soundwire/amd_manager.c.rej" \
			"$SRC/sound/soc/amd/ps/pci-ps.c.rej" \
			"$SRC/sound/soc/amd/ps/ps-common.c.rej"; do
			[[ -f "$rej" ]] && {
				echo "ERROR: Phase 7 correlate patch left $rej" >&2
				exit 1
			}
		done
		phase7_present "$EXPERIMENT" || {
			echo "ERROR: Phase 7 irq-stat-correlate incomplete after patch" >&2
			exit 1
		}
	else
		if [[ -f "$SRC/drivers/soundwire/amd_manager.c.rej" ]]; then
			echo "ERROR: Phase 7 patch left .rej (partial apply)" >&2
			exit 1
		fi
		if ! phase7_present "$EXPERIMENT"; then
			echo "ERROR: Phase 7 $EXPERIMENT incomplete after patch" >&2
			exit 1
		fi
	fi
fi

echo "$EXPERIMENT" >"$STAMP_P7"
date -Is >>"$STAMP_P7"

KVER="$(uname -r)"
BUILD="$KERNEL_BUILD"
echo "==> Rebuilding modules (Phase 7 $EXPERIMENT)"
make -C "$BUILD" M="$(pwd)/drivers/soundwire" CONFIG_SOUNDWIRE=m CONFIG_SOUNDWIRE_AMD=m modules

ko="drivers/soundwire/soundwire-amd.ko"
name="$(basename "$ko")"
dest="/lib/modules/$KVER/kernel/drivers/soundwire/${name}.zst"
ko_ps="sound/soc/amd/ps/snd-pci-ps.ko"
name_ps="$(basename "$ko_ps")"
dest_ps="/lib/modules/$KVER/kernel/sound/soc/amd/ps/${name_ps}.zst"

[[ -f "$ko" ]] || { echo "Missing $ko" >&2; exit 1; }

if phase7_needs_pci_ps "$EXPERIMENT"; then
	kernel_make_pci_ps_modules
	[[ -f "$ko_ps" ]] || { echo "Missing $ko_ps" >&2; exit 1; }
fi

if strings "$ko_ps" 2>/dev/null | grep -q 'PHASE7 ctx=acp fn=irq_handler_enter'; then
	if strings "$ko" 2>/dev/null | grep -q 'fn=intr_decode'; then
		echo "OK: phase7 irq-stat-correlate (0006b + 0007 + correlate) present"
	else
		echo "OK: phase7 0007 pci-ps IRQ delivery trace present"
	fi
elif strings "$ko" | grep -q 'fn=manual_irq_schedule'; then
	echo "OK: phase7 0006a manual_irq_schedule present"
elif strings "$ko" | grep -q 'phase7_delay_ms'; then
	echo "OK: phase7_delay_ms module param present"
elif strings "$ko" | grep -q 'fn=intr_decode'; then
	echo "OK: phase7 0006b intr_decode present"
else
	echo "WARN: no phase7 experiment strings in module" >&2
fi

zstd -19 -f "$ko" -o "/tmp/$name.zst"
echo "==> Installing $dest (requires sudo)"
sudo cp "/tmp/$name.zst" "$dest"
if phase7_needs_pci_ps "$EXPERIMENT"; then
	zstd -19 -f "$ko_ps" -o "/tmp/$name_ps.zst"
	echo "==> Installing $dest_ps (requires sudo)"
	sudo cp "/tmp/$name_ps.zst" "$dest_ps"
fi
sudo depmod -a

STATE="${REPO_ROOT}/validation/.state"
mkdir -p "$STATE"
echo "${DELAY_MS:-0}" >"${STATE}/phase7-delay-ms-suggested"
echo "$EXPERIMENT" >"${STATE}/phase7-experiment"
modinfo -F srcversion "$dest" >"${STATE}/phase7-installed-srcversion"

loaded_sv=""
if [[ -r /sys/module/soundwire_amd/srcversion ]]; then
	loaded_sv="$(cat /sys/module/soundwire_amd/srcversion)"
fi
installed_sv="$(cat "${STATE}/phase7-installed-srcversion")"

echo ""
echo "==> Phase 7 installed: $EXPERIMENT on kernel $KVER"
echo "    installed srcversion: ${installed_sv}"
if [[ -n "$loaded_sv" && "$loaded_sv" != "$installed_sv" ]]; then
	echo ""
	echo "WARN: running soundwire_amd (${loaded_sv}) != installed (${installed_sv})" >&2
	echo "      Reboot before sweep — verify-only will fail until the new .ko is loaded." >&2
elif [[ -n "$loaded_sv" ]]; then
	echo "    running srcversion:   ${loaded_sv} (matches)"
else
	echo "    soundwire_amd not loaded yet"
fi
echo ""
echo "Reboot required after install (mandatory if module was already loaded)."
case "$EXPERIMENT" in
delay-after-d0)
	echo ""
	echo "Before suspend (0 = control baseline):"
	echo "  echo ${DELAY_MS:-0} | sudo tee /sys/module/soundwire_amd/parameters/phase7_delay_ms"
	echo ""
	echo "Sweep: see research/phase-7/experiments/0005-delay-after-d0.md"
	echo "  ${SCRIPT_DIR}/phase7-sweep-pre.sh MS   # before reboot"
	echo "  ${SCRIPT_DIR}/phase7-sweep-post.sh     # after login"
	;;
stat-decode)
	echo ""
	echo "Run: see research/phase-7/experiments/0006b-stat-decode.md"
	echo "  ${SCRIPT_DIR}/phase7-sweep-pre.sh 50   # delay before post_delay snapshot"
	echo "  sudo reboot"
	echo "  ${SCRIPT_DIR}/phase6-hunt.sh post-reboot --notes p7-0006b-d50"
	echo "  systemctl suspend"
	echo "  ${SCRIPT_DIR}/phase6-hunt.sh post-suspend --save-window"
	echo "  journalctl -k -b 0 | grep 'PHASE7 ctx=amd fn=intr_decode'"
	echo ""
	echo "Control (post_D0 only): ${SCRIPT_DIR}/phase7-sweep-pre.sh 0 && reboot"
	;;
validate-manager-mask)
	echo ""
	echo "Run: see research/phase-7/experiments/0006a-validate-manager-mask.md"
	echo "  ${SCRIPT_DIR}/phase7-sweep-pre.sh 50"
	echo "  sudo reboot"
	echo "  ${SCRIPT_DIR}/phase6-hunt.sh post-reboot --notes p7-0006a-d50"
	echo "  systemctl suspend"
	echo "  ${SCRIPT_DIR}/phase6-hunt.sh post-suspend --save-window"
	echo "  journalctl -k -b 0 | grep -E 'manual_irq_schedule|irq_thread_enter|fn=completion'"
	;;
irq-delivery-trace)
	echo ""
	echo "Run: see research/phase-7/experiments/0007-irq-delivery-trace.md"
	echo "  sudo reboot"
	echo "  ${SCRIPT_DIR}/phase6-hunt.sh post-reboot --notes p7-0007-boot"
	echo "  systemctl suspend"
	echo "  ${SCRIPT_DIR}/phase6-hunt.sh post-suspend --save-window"
	echo "  journalctl -k -b 0 | grep 'PHASE7 ctx=acp fn='"
	echo ""
	echo "Compare boot (resume=0 handler hits) vs post-suspend (resume=1) window."
	;;
irq-stat-correlate)
	echo ""
	echo "Run: see research/phase-7/experiments/0007-irq-delivery-trace.md (combined protocol)"
	echo "  ${SCRIPT_DIR}/phase7-irq-snapshot.sh pre-suspend"
	echo "  ${SCRIPT_DIR}/phase7-sweep-pre.sh ${DELAY_MS:-50}   # delay before post_delay snapshot"
	echo "  sudo reboot"
	echo "  ${SCRIPT_DIR}/phase6-hunt.sh post-reboot --notes p7-correlate-d50"
	echo "  systemctl suspend"
	echo "  ${SCRIPT_DIR}/phase7-irq-snapshot.sh post-resume"
	echo "  ${SCRIPT_DIR}/phase6-hunt.sh post-suspend --save-window"
	echo "  journalctl -k -b 0 | grep -E 'PHASE7 ctx=(acp|amd) fn='"
	echo ""
	echo "Close delivery if: t~50ms STAT&mask=0x4 (amd) + no irq_handler_enter (pci) + IRQ164 unchanged."
	;;
esac
