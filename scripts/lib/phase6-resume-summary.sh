#!/usr/bin/env bash
# Resume path YES/NO checklist (post manager_reset). shellcheck shell=bash

phase6_resume_path_summary() {
	local rid="${1:-}"
	local raw post anchor_rid
	local mr=0 irq=0 istat="" istat_nz=0 icntl="" sdw_en="" clk_frame="" istat_bring="" istat_d0="" init_ret="" en_ret="" d0_val="" h_enter=0 th_enter=0 ping_irq=0 ping=0 qw=0 hs=0 att=0 comp=0 wit=0 wiok=0 ret="" early=0 iof=0 sys=0 acp_irq=0 clk_skip=0 clk_done=0 clr=0 fshape=0
	local p7_d0_statm="" p7_delay_statm="" p7_delay_stat1="" p7_manual=0

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

	set +o pipefail
	if echo "$post" | grep -q 'fn=irq_enabled'; then irq=1; fi
	icntl="$(echo "$post" | grep 'fn=intr_cntl_post_enable' | tail -1 | sed -n 's/.*val=0x\([0-9a-fA-F]*\).*/\1/p' || true)"
	istat="$(echo "$post" | grep 'fn=intr_stat_post_enable' | tail -1 | sed -n 's/.*stat=0x\([0-9a-fA-F]*\).*/\1/p' || true)"
	[[ -n "$istat" && "$istat" != "0" ]] && istat_nz=1
	sdw_en="$(echo "$post" | grep 'fn=sdw_en_post_resume' | tail -1 | sed -n 's/.*val=0x\([0-9a-fA-F]*\).*/\1/p' || true)"
	clk_frame="$(echo "$post" | grep 'fn=clk_frame' | tail -1 | sed -n 's/.*val=0x\([0-9a-fA-F]*\).*/\1/p' || true)"
	istat_bring="$(echo "$post" | grep 'fn=intr_stat_post_bringup' | tail -1 | sed -n 's/.*stat=0x\([0-9a-fA-F]*\).*/\1/p' || true)"
	istat_d0="$(echo "$post" | grep 'fn=intr_stat_post_D0' | tail -1 | sed -n 's/.*stat=0x\([0-9a-fA-F]*\).*/\1/p' || true)"
	init_ret="$(echo "$post" | grep 'fn=init_sdw_manager' | tail -1 | sed -n 's/.*ret=\(-*[0-9]*\).*/\1/p' || true)"
	en_ret="$(echo "$post" | grep 'fn=enable_sdw_manager' | tail -1 | sed -n 's/.*ret=\(-*[0-9]*\).*/\1/p' || true)"
	d0_val="$(echo "$post" | grep 'fn=device_state_D0' | tail -1 | sed -n 's/.*val=0x\([0-9a-fA-F]*\).*/\1/p' || true)"
	set +o pipefail
	p7_d0_statm="$(echo "$post" | grep 'fn=intr_decode when=post_D0' | tail -1 | sed -n 's/.*STAT&mask=0x\([0-9a-fA-F]*\).*/\1/p' || true)"
	p7_delay_statm="$(echo "$post" | grep 'fn=intr_decode when=post_delay' | tail -1 | sed -n 's/.*STAT&mask=0x\([0-9a-fA-F]*\).*/\1/p' || true)"
	p7_delay_stat1="$(echo "$post" | grep 'fn=intr_decode when=post_delay' | tail -1 | sed -n 's/.*STAT1=0x\([0-9a-fA-F]*\).*/\1/p' || true)"
	# Pre-compact-line builds: STAT&mask only on continuation lines
	if [[ -z "$p7_d0_statm" ]]; then
		p7_d0_statm="$(echo "$post" | awk '/fn=intr_decode when=post_D0/{show=1;next} /fn=intr_decode when=post_delay/{show=0} show && /STAT&mask=/{print;exit}' | sed -n 's/.*STAT&mask=0x\([0-9a-fA-F]*\).*/\1/p' || true)"
	fi
	if [[ -z "$p7_delay_statm" ]]; then
		p7_delay_block="$(echo "$post" | awk '/fn=intr_decode when=post_delay/{show=1;next} show && /fn=/{exit} show{print}')"
		p7_delay_statm="$(echo "$p7_delay_block" | grep 'STAT&mask=' | tail -1 | sed -n 's/.*STAT&mask=0x\([0-9a-fA-F]*\).*/\1/p' || true)"
		p7_delay_stat1="$(echo "$p7_delay_block" | grep 'STAT1=' | tail -1 | sed -n 's/.*STAT1=0x\([0-9a-fA-F]*\).*/\1/p' || true)"
	fi
	set -o pipefail
	echo "$post" | grep -q 'fn=clk_resume_skip' && clk_skip=1
	echo "$post" | grep -q 'fn=clk_resume_done' && clk_done=1
	echo "$post" | grep -q 'fn=clear_slave_status' && clr=1
	echo "$post" | grep -q 'fn=frameshape_done' && fshape=1
	echo "$post" | grep -q 'fn=irq_handler_enter' && h_enter=1
	echo "$post" | grep -q 'fn=irq_thread_enter' && th_enter=1
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
	echo "$post" | grep -q 'fn=manual_irq_schedule reason=STAT&mask' && p7_manual=1
	set +o pipefail
	ret="$(echo "$post" | grep 'fn=resume_exit' | tail -1 | sed -n 's/.*ret=\(-*[0-9]*\).*/\1/p' || true)"
	set -o pipefail

	# IO_PAGE_FAULT in same resume window (full kmsg, not only PHASE6)
	local bounds since until resume_ts=""
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
	[[ -n "$icntl" ]] && echo "  intr_cntl_post_enable 0x${icntl}" || echo "  intr_cntl_post_enable (log) NO"
	[[ -n "$istat" ]] && echo "  intr_stat_post_enable 0x${istat}" || echo "  intr_stat_post_enable (log) NO"
	[[ -n "$sdw_en" ]] && echo "  sdw_en_post_resume     0x${sdw_en}" || echo "  sdw_en_post_resume (log) NO"
	[[ -n "$clk_frame" ]] && echo "  clk_frame              0x${clk_frame}" || echo "  clk_frame (log) NO"
	[[ -n "$istat_bring" ]] && echo "  intr_stat_post_bringup 0x${istat_bring}" || echo "  intr_stat_post_bringup (log) NO"
	[[ -n "$init_ret" ]] && echo "  init_sdw_manager       ret=${init_ret}" || echo "  init_sdw_manager (log) NO"
	[[ -n "$en_ret" ]] && echo "  enable_sdw_manager     ret=${en_ret}" || echo "  enable_sdw_manager (log) NO"
	echo "  frameshape_done        $(yn "$fshape")"
	[[ -n "$d0_val" ]] && echo "  device_state_D0        0x${d0_val}" || echo "  device_state_D0 (log) NO"
	[[ -n "$istat_d0" ]] && echo "  intr_stat_post_D0      0x${istat_d0}" || echo "  intr_stat_post_D0 (log) NO"
	if [[ -n "$p7_d0_statm" || -n "$p7_delay_statm" ]]; then
		[[ -n "$p7_d0_statm" ]] && echo "  p7 decode post_D0       STAT&mask=0x${p7_d0_statm}"
		[[ -n "$p7_delay_statm" ]] && echo "  p7 decode post_delay   STAT1=0x${p7_delay_stat1:-?} STAT&mask=0x${p7_delay_statm}"
	fi
	if [[ "$clk_done" -eq 1 ]]; then
		echo "  clk_resume             done"
	elif [[ "$clk_skip" -eq 1 ]]; then
		echo "  clk_resume             skip"
	else
		echo "  clk_resume             (log) NO"
	fi
	echo "  clear_slave_status     $(yn "$clr")"
	echo "  irq_handler_enter     $(yn "$h_enter")"
	echo "  irq_thread_enter      $(yn "$th_enter")"
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

	# S1/S2 matrix (0005); Phase 7 decode overrides post-D0-only S1 label
	if [[ -n "$p7_delay_statm" ]]; then
		if [[ "$p7_manual" -eq 1 && "$comp" -eq 1 && "$wit" -eq 0 && "${ret:-}" == "0" ]]; then
			echo "  → PASS-0006a (manual schedule → thread path OK; IRQ delivery still broken)"
		elif [[ "$p7_delay_statm" != "0" && "$h_enter" -eq 0 ]]; then
			echo "  → S1-delayed (post_D0 STAT&mask=0x${p7_d0_statm:-0}; post_delay STAT&mask=0x${p7_delay_statm}; no handler — IRQ delivery?)"
		elif [[ "$p7_delay_statm" = "0" && "$h_enter" -eq 0 ]]; then
			echo "  → S1-delayed? (post_delay STAT&mask=0 — no pending IRQ at +delay)"
		fi
	elif [[ "$irq" -eq 1 && -n "$istat" ]]; then
		if [[ "$istat_nz" -eq 0 && "$h_enter" -eq 0 ]]; then
			echo "  → S1 (stat=0, no handler — no hardware event)"
		elif [[ "$istat_nz" -eq 1 && "$h_enter" -eq 0 ]]; then
			echo "  → S2 (stat≠0, no handler — IRQ routing/mask)"
		elif [[ "$istat_nz" -eq 1 && "$h_enter" -eq 1 && "$th_enter" -eq 0 ]]; then
			echo "  → post-ISR? (handler ran, irq_thread never)"
		elif [[ "$h_enter" -eq 1 && "$th_enter" -eq 1 ]]; then
			echo "  → past thread entry (bisect SDW path)"
		elif [[ "$istat_nz" -eq 0 && "$h_enter" -eq 1 ]]; then
			echo "  → check instrumentation (stat=0 but handler ran)"
		fi
	elif [[ "$mr" -eq 1 && "$irq" -eq 1 && "$ping_irq" -eq 0 && "$acp_irq" -eq 0 ]]; then
		echo "  → S1/S2? (pre-0005 — rebuild for intr_stat/handler probes)"
	elif [[ "$mr" -eq 1 && "$irq" -eq 1 && -z "$icntl" && -n "$istat" ]]; then
		echo "  → pre-0006? (no intr_cntl — rebuild for ACP block snapshot)"
	elif [[ "$mr" -eq 1 && "$irq" -eq 1 && -n "$init_ret" && "$init_ret" -eq 0 && -n "$en_ret" && "$en_ret" -eq 0 && "$fshape" -eq 1 && -n "$istat_d0" && "$istat_d0" = "0" && "$h_enter" -eq 0 ]]; then
		echo "  → kick complete, STAT=0 post-D0 — HW did not assert first event"
	elif [[ "$mr" -eq 1 && "$irq" -eq 1 && -z "$init_ret" ]]; then
		echo "  → pre-0007? (no kick probes — rebuild for resume kick trace)"
	elif [[ "$mr" -eq 1 && "$acp_irq" -eq 1 && "$ping_irq" -eq 0 ]]; then
		echo "  → S3? (ACP IRQ/handler, irq_thread never ran)"
	elif [[ "$mr" -eq 1 && "$ping_irq" -eq 1 && "$qw" -eq 0 ]]; then
		echo "  → S4? (ping_irq, no queue_work — empty status)"
	elif [[ "$qw" -eq 1 && "$att" -eq 0 && "$comp" -eq 0 ]]; then
		echo "  → H-SDW? (queue_work, no bus ATTACHED/completion)"
	elif [[ "$att" -eq 1 && "$comp" -eq 1 ]]; then
		echo "  → Case D (PASS path)"
	elif [[ "$mr" -eq 1 && "$irq" -eq 0 ]]; then
		echo "  → pre-0004? (no irq_enabled log — rebuild module)"
	fi
	echo ""
}
