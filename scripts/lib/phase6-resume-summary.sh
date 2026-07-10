#!/usr/bin/env bash
# Resume path YES/NO checklist (post manager_reset). shellcheck shell=bash

phase6_resume_path_summary() {
	local rid="${1:-}"
	local raw post anchor_rid
	local mr=0 irq=0 ping_irq=0 ping=0 qw=0 hs=0 att=0 comp=0 wit=0 wiok=0 ret="" early=0 iof=0 sys=0 acp_irq=0

	raw="$(phase6_lines_for_run "$rid" "resume_window")"
	[[ -n "$raw" ]] || {
		echo "Resume path: (no data)"
		return
	}

	# Post-reset slice: from first amd manager_reset or bus manager_reset
	post=""
	while IFS= read -r line; do
		[[ -z "$line" ]] && continue
		body="$(echo "$line" | sed 's/^[^ ]* [^ ]* [^ ]* [^ ]* //')"
		if [[ -z "$post" ]]; then
			if echo "$body" | grep -qE 'ctx=amd fn=manager_reset|reason=manager_reset'; then
				post="__START__"
				anchor_rid="$(echo "$body" | sed -n 's/.*resume=\([0-9]*\).*/\1/p')"
			fi
			continue
		fi
		post+="${line}"$'\n'
	done <<<"$raw"

	[[ -n "$post" ]] || post="$raw"

	echo "$raw" | grep -qE 'ctx=amd fn=manager_reset|reason=manager_reset' && mr=1
	echo "$raw" | grep -q 'ctx=amd fn=resume_enter.*pm=system_resume' && sys=1

	if echo "$post" | grep -q 'fn=irq_enabled'; then irq=1; fi
	if echo "$post" | grep -q 'fn=ping_irq'; then ping_irq=1; fi
	if echo "$post" | grep -q 'fn=ping_status'; then ping=1; fi
	if echo "$post" | grep -q 'fn=queue_work'; then qw=1; fi
	if echo "$post" | grep -q 'fn=sdw0_irq'; then acp_irq=1; fi
	if echo "$post" | grep -q 'fn=handle_status'; then hs=1; fi
	if echo "$post" | grep -q 'fn=state_change.*new=ATTACHED'; then att=1; fi
	if echo "$post" | grep -q 'fn=completion'; then comp=1; fi
	if echo "$post" | grep -q 'fn=wait_init_timeout'; then wit=1; fi
	if echo "$post" | grep -q 'fn=wait_init_ok'; then wiok=1; fi
	if echo "$post" | grep -q 'fn=resume_early_exit'; then early=1; fi
	ret="$(echo "$post" | grep 'fn=resume_exit' | tail -1 | sed -n 's/.*ret=\(-*[0-9]*\).*/\1/p')"

	# IO_PAGE_FAULT in same resume window (full kmsg, not only PHASE6)
	local bounds since until resume_ts
	if [[ -n "$rid" ]]; then
		resume_ts="$(phase6_run_resume_ts "$rid" 2>/dev/null || true)"
	fi
	if [[ -z "$resume_ts" ]]; then
		resume_ts="$(phase6_journal_last_suspend_exit 2>/dev/null || true)"
	fi
	if [[ -n "$resume_ts" ]]; then
		bounds="$(phase6_resume_window_bounds "$resume_ts")"
		since="${bounds%%$'\t'*}"
		until="${bounds#*$'\t'}"
		journalctl -k -b 0 --no-pager --since "$since" --until "$until" 2>/dev/null \
			| grep -q 'IO_PAGE_FAULT' && iof=1
	fi

	yn() { [[ "${1:-0}" -eq 1 ]] && echo "YES" || echo "NO"; }

	echo "=== Resume path (post manager_reset) ==="
	[[ -n "$rid" ]] && echo "  run: ${rid}${anchor_rid:+  resume=${anchor_rid}}"
	echo "  system_resume_enter   $(yn "$sys")"
	echo "  manager_reset         $(yn "$mr")"
	echo "  irq_enabled           $(yn "$irq")"
	echo "  acp sdw0_irq (log)    $(yn "$acp_irq")"
	echo "  ping_irq (log)        $(yn "$ping_irq")"
	echo "  ping_status (log)     $(yn "$ping")"
	echo "  queue_work (log)      $(yn "$qw")"
	echo "  handle_status (log)   $(yn "$hs")"
	echo "  UNATTACHED→ATTACHED   $(yn "$att")"
	echo "  completion            $(yn "$comp")"
	echo "  wait_init_ok          $(yn "$wiok")"
	echo "  wait_init_timeout     $(yn "$wit")"
	echo "  resume_early_exit     $(yn "$early")"
	echo "  resume_ret            ${ret:-?}"
	echo "  IO_PAGE_FAULT (window) $(yn "$iof")"
	echo ""

	if [[ "$wit" -eq 1 ]]; then
		echo "  fail_class: FAIL-1 (RT721 waited on initialization_complete)"
	elif [[ "$early" -eq 1 && "$wit" -eq 0 ]]; then
		echo "  fail_class: FAIL-2 (RT721 resume_early_exit, no wait_init)"
	fi

	# Case A/B/C/D sketch (log-based, IRQ-aware)
	if [[ "$mr" -eq 1 && "$irq" -eq 1 && "$ping_irq" -eq 0 && "$acp_irq" -eq 0 ]]; then
		echo "  → H1? (irq_enabled, no ACP IRQ / ping_irq)"
	elif [[ "$mr" -eq 1 && "$acp_irq" -eq 1 && "$ping_irq" -eq 0 ]]; then
		echo "  → H1? (ACP IRQ, irq_thread never ran)"
	elif [[ "$mr" -eq 1 && "$ping_irq" -eq 1 && "$qw" -eq 0 ]]; then
		echo "  → H2? (ping_irq, no queue_work — empty status or PREQ-only)"
	elif [[ "$qw" -eq 1 && "$att" -eq 0 && "$comp" -eq 0 ]]; then
		echo "  → H3? (queue_work, no bus ATTACHED/completion)"
	elif [[ "$att" -eq 1 && "$comp" -eq 1 ]]; then
		echo "  → Case D (PASS path)"
	elif [[ "$mr" -eq 1 && "$ping" -eq 0 && "$ping_irq" -eq 0 ]]; then
		echo "  → Case A? (no ping path after reset — pre-0004 trace)"
	fi
	echo ""
}
