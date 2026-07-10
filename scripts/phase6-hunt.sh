#!/usr/bin/env bash
# Phase 6 — post-reboot / post-suspend workflow (bounded PASS hunt).
#
#   post-reboot [--notes LABEL] [--no-arm] [--no-mask]
#   post-suspend [--save-window]
#
# Typical cycle:
#   sudo reboot
#   ./scripts/phase6-hunt.sh post-reboot --notes run-17-attempt
#   systemctl suspend
#   ./scripts/phase6-hunt.sh post-suspend
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$REPO"
HUNT_LOG="${REPO}/validation/phase6-hunt-log.csv"
STATE_DIR="${REPO}/validation/.state"

# shellcheck source=lib/phase6-journal.sh
. "${SCRIPT_DIR}/lib/phase6-journal.sh"

cmd="${1:-}"
shift || true

usage() {
	cat <<'EOF'
Usage:
  ./scripts/phase6-hunt.sh post-reboot [--notes LABEL] [--no-arm] [--no-mask]
  ./scripts/phase6-hunt.sh post-suspend [--save-window]

post-reboot  — after clean reboot: verify modules, mask rebind, arm capture
post-suspend — immediately after wake: state machine + kernel PASS/FAIL verdict
EOF
}

phase6_ko_has_trace() {
	local ko_zst="$1" pattern="$2"
	[[ -f "$ko_zst" ]] || return 1
	# grep -q closes the pipe early; with pipefail the pipeline returns SIGPIPE (141).
	set +o pipefail
	zstd -d -qc "$ko_zst" 2>/dev/null | strings | grep -Fq -- "$pattern"
	local rc=$?
	set -o pipefail
	[[ "$rc" -eq 0 ]]
}

phase6_mask_px13_recovery() {
	local u
	for u in px13-audio-rebind.service px13-audio-resume.service; do
		if systemctl list-unit-files "$u" &>/dev/null; then
			echo "==> mask --runtime $u"
			sudo systemctl mask --runtime "$u"
		else
			echo "==> skip $u (not installed)"
		fi
	done
}

phase6_hunt_init_log() {
	mkdir -p "${REPO}/validation"
	if [[ ! -f "$HUNT_LOG" ]]; then
		echo "ts,boot_id,notes,kernel_witness,fail_class,resume_n,intr_stat_d0,irq_handler,completion,wait_init_timeout,rt721_ret,audio_sink" \
			>"$HUNT_LOG"
	fi
}

phase6_hunt_classify_window() {
	local raw="$1"
	local witness="UNKNOWN" fail_class="" resume_n="" istat_d0="" h=0 comp=0 wit=0 rt721=""

	raw="$(printf '%s' "$raw")"
	echo "$raw" | grep -q 'fn=wait_init_timeout' && wit=1
	echo "$raw" | grep -q 'fn=resume_early_exit' && fail_class="FAIL-2"
	[[ -z "$fail_class" && "$wit" -eq 1 ]] && fail_class="FAIL-1"
	echo "$raw" | grep -q 'fn=irq_handler_enter' && h=1
	echo "$raw" | grep -q 'fn=completion' && comp=1
	# grep no-match + pipefail aborts under set -e inside $(…).
	set +o pipefail
	resume_n="$(echo "$raw" | grep 'fn=manager_reset' | tail -1 | sed -n 's/.*resume=\([0-9]*\).*/\1/p' || true)"
	istat_d0="$(echo "$raw" | grep 'fn=intr_stat_post_D0' | tail -1 | sed -n 's/.*stat=0x\([0-9a-fA-F]*\).*/\1/p' || true)"
	rt721="$(echo "$raw" | grep 'fn=resume_exit' | tail -1 | sed -n 's/.*ret=\(-*[0-9]*\).*/\1/p' || true)"
	set -o pipefail

	if [[ "$h" -eq 1 && "$comp" -eq 1 && "$wit" -eq 0 ]]; then
		witness="PASS"
	elif [[ "$fail_class" == "FAIL-1" ]]; then
		witness="FAIL-1"
	elif [[ "$fail_class" == "FAIL-2" ]]; then
		witness="FAIL-2"
	elif echo "$raw" | grep -q 'fn=manager_reset'; then
		witness="PARTIAL"
	else
		witness="NO_DATA"
	fi

	printf '%s|%s|%s|%s|%d|%d|%d|%s\n' \
		"$witness" "$fail_class" "$resume_n" "$istat_d0" \
		"$h" "$comp" "$wit" "${rt721:--}"
}

phase6_hunt_read_classify() {
	local witness fail_class resume_n istat_d0 h comp wit rt721
	IFS='|' read -r witness fail_class resume_n istat_d0 h comp wit rt721 < <(
		phase6_hunt_classify_window "$1"
	)
	[[ "$rt721" == "-" ]] && rt721=""
	printf '%s|%s|%s|%s|%s|%s|%s|%s\n' \
		"$witness" "$fail_class" "$resume_n" "$istat_d0" "$h" "$comp" "$wit" "$rt721"
}

case "$cmd" in
post-reboot)
	NOTES="run-$(date +%Y%m%d-%H%M)"
	ARM=1
	MASK=1
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--notes) NOTES="${2:?}"; shift 2 ;;
		--no-arm) ARM=0; shift ;;
		--no-mask) MASK=0; shift ;;
		-h|--help) usage; exit 0 ;;
		*) echo "Unknown: $1" >&2; usage; exit 1 ;;
		esac
	done

	KVER="$(uname -r)"
	AMD_KO="/lib/modules/$KVER/kernel/drivers/soundwire/soundwire-amd.ko.zst"
	PS_KO="/lib/modules/$KVER/kernel/sound/soc/amd/ps/snd-pci-ps.ko.zst"

	echo "=== Phase 6 post-reboot $(date -Is) ==="
	echo "  kernel: $KVER"
	echo "  boot_id: $(cat /proc/sys/kernel/random/boot_id)"
	echo "  notes: $NOTES"
	echo ""

	echo "==> Module trace check (0003–0007)"
	missing=0
	if phase6_ko_has_trace "$AMD_KO" 'fn=device_state_D0'; then
		echo "  OK soundwire-amd (0007)"
	elif phase6_ko_has_trace "$AMD_KO" 'fn=intr_cntl_post_enable'; then
		echo "  WARN soundwire-amd (0006 only — rebuild: ./scripts/build-phase6-amd-trace.sh)" >&2
		missing=1
	else
		echo "  FAIL soundwire-amd — no PHASE6 strings" >&2
		missing=1
	fi
	if phase6_ko_has_trace "$PS_KO" 'fn=irq_handler_enter'; then
		echo "  OK snd-pci-ps (0005)"
	else
		echo "  FAIL snd-pci-ps — no irq_handler_enter" >&2
		missing=1
	fi
	[[ "$missing" -eq 0 ]] || {
		echo ""
		echo "Rebuild/install: ./scripts/build-phase6-amd-trace.sh && sudo reboot" >&2
		exit 1
	}

	if [[ "$MASK" -eq 1 ]]; then
		echo ""
		phase6_mask_px13_recovery
	fi

	mkdir -p "$STATE_DIR"
	echo "$NOTES" >"${STATE_DIR}/phase6-hunt-notes"

	if [[ "$ARM" -eq 1 ]]; then
		echo ""
		echo "==> arm chronology worker"
		"${SCRIPT_DIR}/phase6-experiment.sh" arm --force --notes "$NOTES"
	fi

	phase6_hunt_init_log

	echo ""
	echo "=== Next ==="
	echo "  systemctl suspend"
	echo "  # immediately after wake:"
	echo "  ./scripts/phase6-hunt.sh post-suspend"
	;;

post-suspend)
	SAVE_WINDOW=0
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--save-window) SAVE_WINDOW=1; shift ;;
		-h|--help) usage; exit 0 ;;
		*) echo "Unknown: $1" >&2; usage; exit 1 ;;
		esac
	done

	NOTES="$(cat "${STATE_DIR}/phase6-hunt-notes" 2>/dev/null || echo "")"
	exit_ts="$(phase6_journal_last_suspend_exit 2>/dev/null || true)"
	if [[ -z "$exit_ts" ]]; then
		echo "ERROR: no PM: suspend exit in this boot — did you suspend?" >&2
		exit 1
	fi

	raw="$(phase6_journal_extract_window "$exit_ts")"
	IFS='|' read -r witness fail_class resume_n istat_d0 h comp wit rt721 < <(
		phase6_hunt_read_classify "$raw"
	)
	set +o pipefail
	p7_delay_stat="$(echo "$raw" | grep 'fn=intr_stat_post_delay' | tail -1 | sed -n 's/.*stat=0x\([0-9a-fA-F]*\).*/\1/p' || true)"
	set -o pipefail

	echo "=== Phase 6 post-suspend $(date -Is) ==="
	echo "  resume_exit: $exit_ts"
	echo "  notes: ${NOTES:-?}"
	echo "  kernel_witness: $witness"
	[[ -n "$fail_class" ]] && echo "  fail_class: $fail_class"
	[[ -n "$resume_n" ]] && echo "  resume_n: $resume_n"
	[[ -n "$istat_d0" ]] && echo "  intr_stat_post_D0: 0x${istat_d0}"
	[[ -n "$p7_delay_stat" ]] && echo "  intr_stat_post_delay: 0x${p7_delay_stat}"
	echo "  irq_handler: $([[ "$h" -eq 1 ]] && echo YES || echo NO)"
	echo "  completion:  $([[ "$comp" -eq 1 ]] && echo YES || echo NO)"
	echo "  wait_init_timeout: $([[ "$wit" -eq 1 ]] && echo YES || echo NO)"
	echo ""

	if [[ "$witness" == "NO_DATA" ]]; then
		echo "WARN: last resume window has no manager_reset — wrong cycle or incomplete suspend" >&2
		echo "  journal slice:" >&2
		echo "$raw" | sed 's/^/    /' >&2
		exit 2
	fi

	if [[ "$witness" == "PASS" ]]; then
		echo "*** KERNEL WITNESS PASS — save logs and compare to 0015 ***"
	fi

	echo "==> state machine"
	"${SCRIPT_DIR}/phase6-state-machine.sh" --last-resume

	if [[ "$SAVE_WINDOW" -eq 1 ]]; then
		out="${REPO}/validation/phase6-runs/hunt-${NOTES:-$(date +%Y%m%d-%H%M%S)}"
		mkdir -p "$out"
		printf '%s\n' "$raw" >"$out/kmsg-phase6-window.log"
		echo "==> saved $out/kmsg-phase6-window.log"
	fi

	# Best-effort userspace sink (not kernel witness)
	sink="?"
	if command -v wpctl &>/dev/null; then
		sink="$(wpctl status 2>/dev/null | awk '/\*/{print $2; exit}' || echo "?")"
	fi

	phase6_hunt_init_log
	echo "$(date -Is),$(cat /proc/sys/kernel/random/boot_id),${NOTES},${witness},${fail_class},${resume_n},${istat_d0},$([[ $h -eq 1 ]] && echo Y || echo N),$([[ $comp -eq 1 ]] && echo Y || echo N),$([[ $wit -eq 1 ]] && echo Y || echo N),${rt721},${sink}" \
		>>"$HUNT_LOG"

	echo ""
	echo "==> hunt log: $HUNT_LOG (tail)"
	tail -3 "$HUNT_LOG"

	pass_n="$(awk -F, 'NR>1 && $4=="PASS" {c++} END{print c+0}' "$HUNT_LOG")"
	fail1_n="$(awk -F, 'NR>1 && $4=="FAIL-1" {c++} END{print c+0}' "$HUNT_LOG")"
	attempts="$(awk -F, 'NR>1 {c++} END{print c+0}' "$HUNT_LOG")"
	echo ""
	echo "  attempts=$attempts  kernel_PASS=$pass_n  FAIL-1=$fail1_n"
	if [[ "$pass_n" -ge 1 ]]; then
		echo "  → golden diff ready: compare post-suspend PASS vs run 0015"
	elif [[ "$attempts" -ge 20 ]]; then
		echo "  → ≥20 attempts, 0 PASS: document scenario 3 (see research/phase-6/UPSTREAM-STRATEGY.md)"
	else
		echo "  → next: sudo reboot && ./scripts/phase6-hunt.sh post-reboot --notes run-NN"
	fi
	;;

*)
	usage
	exit 1
	;;
esac
