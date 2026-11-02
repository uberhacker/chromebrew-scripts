#!/usr/bin/env bash
# lib/core/runner.sh - step execution, result tracking and the summary.
#
# A command is a sequence of steps; a step is a function. It reports its
# outcome by calling one of
#   step_ok NOTE | step_updated NOTE | step_skip NOTE | step_fail NOTE |
#   step_dry NOTE | step_warn NOTE
# If it returns non-zero without reporting, the step is recorded as failed.
# There is deliberately no `set -e`: every step handles its own errors, and
# the command decides whether a failed step stops the rest (run_step returns
# 1 for a failed step so that `run_step ... || return 1` reads naturally).

CBS_STEP_NAMES=()
CBS_STEP_RESULTS=()
CBS_STEP_NOTES=()
STEP_RESULT=""
STEP_NOTE=""

step_ok()      { STEP_RESULT=ok;      STEP_NOTE="${1:-}"; }
step_updated() { STEP_RESULT=updated; STEP_NOTE="${1:-}"; }
step_skip()    { STEP_RESULT=skipped; STEP_NOTE="${1:-}"; }
step_fail()    { STEP_RESULT=failed;  STEP_NOTE="${1:-}"; }
step_dry()     { STEP_RESULT=dry-run; STEP_NOTE="${1:-}"; }
step_warn()    { STEP_RESULT=warn;    STEP_NOTE="${1:-}"; }

# runner_record NAME RESULT NOTE
runner_record() {
  CBS_STEP_NAMES+=("$1")
  CBS_STEP_RESULTS+=("$2")
  CBS_STEP_NOTES+=("$3")
}

# runner_print_result NAME RESULT NOTE: the one-line status after a step.
runner_print_result() {
  local name="$1" result="$2" note="$3"
  case "$result" in
    ok)      log_ok "$name: ${note:-done}" ;;
    updated) log_updated "$name: ${note:-changed}" ;;
    skipped) log_skipped "$name: ${note:-skipped}" ;;
    failed)  log_error "$name: ${note:-failed}" ;;
    dry-run) log_dry "$name: ${note:-dry run}" ;;
    warn)    log_warn "$name: ${note:-warning}" ;;
  esac
}

# run_step NAME FUNC [ARGS...]: run one step, record and print its result.
# Returns 1 when the step failed, 0 otherwise.
run_step() {
  local name="$1" func="$2"; shift 2
  local rc=0
  log_step "$name"
  STEP_RESULT=""; STEP_NOTE=""
  "$func" "$@" || rc=$?
  if [ -z "$STEP_RESULT" ]; then
    if [ "$rc" -eq 0 ]; then
      STEP_RESULT=ok
    else
      STEP_RESULT=failed
      STEP_NOTE="${STEP_NOTE:-$(rc_note "$rc")}"
    fi
  fi
  runner_record "$name" "$STEP_RESULT" "$STEP_NOTE"
  runner_print_result "$name" "$STEP_RESULT" "$STEP_NOTE"
  [ "$STEP_RESULT" != failed ]
}

# summary_counts: prints "ok updated skipped failed dry-run warn" counts.
summary_counts() {
  local r ok=0 up=0 sk=0 fa=0 dr=0 wa=0
  for r in "${CBS_STEP_RESULTS[@]-}"; do
    case "$r" in
      ok) ok=$((ok + 1)) ;;
      updated) up=$((up + 1)) ;;
      skipped) sk=$((sk + 1)) ;;
      failed) fa=$((fa + 1)) ;;
      dry-run) dr=$((dr + 1)) ;;
      warn) wa=$((wa + 1)) ;;
    esac
  done
  printf '%s %s %s %s %s %s\n' "$ok" "$up" "$sk" "$fa" "$dr" "$wa"
}

# summary_print: one line per step and the totals; returns 1 when anything
# failed. Nothing is printed when no step ran (a report command).
summary_print() {
  local i name result note icon color width=8
  local n=${#CBS_STEP_NAMES[@]}
  local c_ok c_up c_sk c_fa c_dr c_wa totals
  [ "$n" -gt 0 ] || return 0
  log_plain ""
  log_plain "${C_BOLD}Summary${C_RESET}$([ "$CBS_DRY_RUN" = 1 ] && printf ' %s(dry run)%s' "$C_MAGENTA" "$C_RESET")"
  for ((i = 0; i < n; i++)); do
    [ "${#CBS_STEP_NAMES[i]}" -gt "$width" ] && width=${#CBS_STEP_NAMES[i]}
  done
  for ((i = 0; i < n; i++)); do
    name="${CBS_STEP_NAMES[i]}"; result="${CBS_STEP_RESULTS[i]}"; note="${CBS_STEP_NOTES[i]}"
    case "$result" in
      ok)      icon="$I_OK";      color="$C_GREEN" ;;
      updated) icon="$I_UPDATED"; color="$C_CYAN" ;;
      skipped) icon="$I_SKIPPED"; color="$C_DIM" ;;
      failed)  icon="$I_FAILED";  color="$C_RED" ;;
      dry-run) icon="$I_DRY";     color="$C_MAGENTA" ;;
      warn)    icon="$I_WARN";    color="$C_YELLOW" ;;
      *)       icon="?";          color="" ;;
    esac
    log_plain "$(printf '  %s%-2s %-8s%s %-*s %s' "$color" "$icon" "$result" "$C_RESET" "$width" "$name" "$note")"
  done
  read -r c_ok c_up c_sk c_fa c_dr c_wa <<< "$(summary_counts)"
  totals="  $c_ok ok, $c_up updated, $c_sk skipped, $c_fa failed, $c_dr dry-run"
  [ "$c_wa" -gt 0 ] && totals+=", $c_wa warning(s)"
  log_plain "$totals"
  [ "$c_fa" -eq 0 ]
}
