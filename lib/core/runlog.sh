#!/usr/bin/env bash
# lib/core/runlog.sh - the per-run log file.
#
# Every real or dry run of a command writes a log (unless LOGGING=0 /
# --no-log): a header describing the run, then every line the toolkit
# prints, the verbose-only lines (commands, details), and the output, exit
# status and duration of every command run through the runners. Lines are
# timestamped and colour-free (log.sh's _log_file does the writing).
# CBS_LOG_FILE is the open log's path; empty means no log.
#
# --help, --version and usage errors never open a log.
#
# Location: --log FILE, else LOG_DIR, else /var/log/chromebrew-scripts for
# root and ${XDG_STATE_HOME:-~/.local/state}/chromebrew-scripts for a user.
# Files are named YYYYmmdd-HHMMSS-<command>-PID.log, "latest.log" points at
# the newest, and only the newest LOG_KEEP (default 20, 0 = all) are kept.
# The directory is created 0700 and the files 0600: they show package
# lists, paths and the hostname.

# runlog_default_dir: where logs go when LOG_DIR is not set.
runlog_default_dir() {
  if is_root; then
    printf '%s/var/log/chromebrew-scripts\n' "$CBS_ROOT"
  else
    printf '%s/chromebrew-scripts\n' "${XDG_STATE_HOME:-$CBS_HOME/.local/state}"
  fi
}

# runlog_prune DIR KEEP: remove all but the newest KEEP logs in DIR. The
# names start with the timestamp, so the glob order is oldest first.
runlog_prune() {
  local dir="$1" keep="$2" n i
  local -a logs=()
  [ "$keep" -gt 0 ] 2>/dev/null || return 0
  for i in "$dir"/[0-9]*-*.log; do
    [ -f "$i" ] && logs+=("$i")
  done
  n=${#logs[@]}
  for ((i = 0; i < n - keep; i++)); do
    rm -f -- "${logs[i]}"
  done
}

# runlog_header CMD ARGS...: what this run is (CMD: the command name as
# invoked, ARGS: the rest of the command line).
runlog_header() {
  local cmd="$1"; shift
  [ -n "$CBS_LOG_FILE" ] || return 0
  {
    printf '# %s\n' "$(version_string)"
    printf '# started  %(%Y-%m-%d %H:%M:%S %z)T\n' -1
    printf '# host     %s\n' "$(uname -n 2>/dev/null || echo unknown) ($(uname -sr 2>/dev/null) $(uname -m 2>/dev/null))"
    printf '# os       %s\n' "$(chromeos_describe)"
    if [ -n "$CBS_OS_BOARD" ] || [ -n "$CBS_OS_BUILD_TYPE" ]; then
      printf '# board    %s%s (from lsb-release, informational)\n' "${CBS_OS_BOARD:-unknown}" "${CBS_OS_BUILD_TYPE:+, $CBS_OS_BUILD_TYPE}"
    fi
    printf '# user     %s (uid %s)\n' "$CBS_CUR_USER" "$CBS_UID"
    printf '# command  %s%s\n' "$cmd" "${*:+ $(cbs_quote "$@")}"
    printf '# program  %s%s\n' "$CBS_BIN" "$([ "$CBS_BUNDLED" = 1 ] && printf ' (single file)')"
    printf '# mode     %s\n' "$([ "$CBS_DRY_RUN" = 1 ] && printf 'dry run' || printf 'real run')"
    config_print_nondefault '# setting  '
    printf '\n'
  } >> "$CBS_LOG_FILE"
}

# runlog_open CMD ARGS...: open the run log (CMD and ARGS for the header).
# Never fatal: a log that cannot be written is a warning.
runlog_open() {
  local dir file
  if [ -n "$CBS_LOG_PATH" ]; then
    file="$CBS_LOG_PATH"
    dir=""
  else
    cfg_bool LOGGING || return 0
    dir=$(cfg LOG_DIR)
    [ -n "$dir" ] || dir=$(runlog_default_dir)
    if ! (umask 077; mkdir -p -- "$dir") 2>/dev/null; then
      log_warn "cannot create log directory $dir; this run is not logged (LOG_DIR or --no-log)"
      return 0
    fi
    file="$dir/$(printf '%(%Y%m%d-%H%M%S)T' -1)-${1:-run}-$$.log"
  fi
  if ! (umask 077; : >> "$file") 2>/dev/null; then
    log_warn "cannot write log file $file; this run is not logged"
    return 0
  fi
  CBS_LOG_FILE="$file"
  runlog_header "$@"
  if [ -n "$dir" ]; then
    ln -sfn -- "${file##*/}" "$dir/latest.log" 2>/dev/null || true
    runlog_prune "$dir" "$(cfg LOG_KEEP)"
  fi
}

# runlog_close RC: final line with the exit status; no more is logged.
runlog_close() {
  [ -n "$CBS_LOG_FILE" ] || return 0
  printf '\n# finished %(%Y-%m-%d %H:%M:%S %z)T, exit status %s, %ss\n' -1 "$1" "$SECONDS" >> "$CBS_LOG_FILE"
  CBS_LOG_FILE=""
}
