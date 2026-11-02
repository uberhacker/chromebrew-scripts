#!/usr/bin/env bash
# lib/core/util.sh - shared helpers: the invoking user, sudo, command
# runners with timeouts and logging, temp files, downloads with checksum
# verification, quoting and the [y/N] confirmation.
#
# Relocation knobs (tests and CI only; see README "Environment variables"):
#   CBS_ROOT   prefix prepended to every filesystem root the toolkit touches
#   CBS_HOME   the home directory (config, state/logs, .bashrc); default $HOME
#   CBS_SUDO   privilege-escalation command (default sudo; empty = none)

: "${CBS_DRY_RUN:=0}"
: "${CBS_YES:=0}"
: "${CBS_TIMEOUT:=300}"            # seconds for mount, make_dev_ssd.sh, ...
: "${CBS_CREW_TIMEOUT:=3600}"      # seconds for crew and the Chromebrew installer
: "${CBS_DOWNLOAD_TIMEOUT:=300}"   # seconds for a download
CBS_ROOT="${CBS_ROOT:-}"
CBS_HOME="${CBS_HOME:-${HOME:-/home/chronos/user}}"
CBS_SUDO="${CBS_SUDO-sudo}"
CBS_TMP_PATHS=()

has_cmd() { command -v "$1" >/dev/null 2>&1; }

is_root() { [ "$(id -u)" -eq 0 ]; }

# user_init: who is running this.
user_init() {
  CBS_UID=$(id -u)
  CBS_CUR_USER=$(id -un 2>/dev/null || printf 'uid%s' "$CBS_UID")
  export CBS_HOME
}

# ---------------------------------------------------------------------------
# Quoting
# ---------------------------------------------------------------------------
# cbs_quote ARGS...: a command line for display, quoting only what needs it.
cbs_quote() {
  local arg out=''
  for arg in "$@"; do
    if [[ "$arg" =~ ^[A-Za-z0-9_./=:,+@%-]+$ ]]; then
      out+="$arg "
    else
      out+="$(printf '%q' "$arg") "
    fi
  done
  printf '%s' "${out% }"
}

# ---------------------------------------------------------------------------
# Command runners
# ---------------------------------------------------------------------------
# All runners: stdin from /dev/null, wrapped in timeout, logged in verbose
# mode, and with a run log open the command's output goes to the log too,
# followed by its exit status and duration.
#   run CMD...        run now, also in a dry run (read-only probes)
#   run_sudo CMD...   the same through CBS_SUDO
#   do_run CMD...     run, or only report "would run" in a dry run
#   do_sudo CMD...    the same through CBS_SUDO
#   do_pipe DESC FUNC ARGS...
#                     for a pipeline wrapped in a shell function (yes | ...);
#                     DESC is what the dry run and the log show. No timeout
#                     is added: put it inside the pipeline.
# Env: CBS_RUN_TIMEOUT overrides the timeout for one call (0 = none).

_timeout_cmd() {
  local secs="${CBS_RUN_TIMEOUT:-$CBS_TIMEOUT}"
  if has_cmd timeout && [ "$secs" != 0 ]; then
    printf 'timeout -k 10 %s' "$secs"
  fi
}

# _run_logged CMD...: run CMD; with a run log open, copy its stdout and
# stderr there as well and record how it ended. Output still reaches the
# caller unchanged, so $(run ...) captures work as before. (stderr is copied
# asynchronously and may land a line late.)
_run_logged() {
  [ -n "${CBS_LOG_FILE:-}" ] || { "$@"; return; }
  local rc start=$SECONDS log="$CBS_LOG_FILE"
  { "$@" 2> >(tee -a "$log" >&2); } | tee -a "$log"
  rc=${PIPESTATUS[0]}
  printf '%(%H:%M:%S)T   -> exit %s after %ss\n' -1 "$rc" "$((SECONDS - start))" >> "$log"
  return "$rc"
}

# _sudo_prefix: the words that run something through CBS_SUDO, if any.
_sudo_prefix() {
  [ -n "$CBS_SUDO" ] && printf '%s' "$CBS_SUDO"
}

run() {
  local tmo
  tmo=$(_timeout_cmd)
  log_cmd "$(cbs_quote "$@")"
  # shellcheck disable=SC2086
  _run_logged $tmo "$@" </dev/null
}

run_sudo() {
  local pfx
  pfx=$(_sudo_prefix)
  # shellcheck disable=SC2086
  run $pfx "$@"
}

do_run() {
  if [ "$CBS_DRY_RUN" = 1 ]; then
    log_dry "would run: $(cbs_quote "$@")"
    return 0
  fi
  run "$@"
}

do_sudo() {
  local pfx
  pfx=$(_sudo_prefix)
  # shellcheck disable=SC2086
  do_run $pfx "$@"
}

do_pipe() {
  local desc="$1"; shift
  if [ "$CBS_DRY_RUN" = 1 ]; then
    log_dry "would run: $desc"
    return 0
  fi
  log_cmd "$desc"
  _run_logged "$@"
}

# yes_pipe CMD...: feed an endless stream of "y" to CMD and return CMD's
# exit status (yes dying of SIGPIPE must not trip pipefail).
yes_pipe() {
  local status=0
  { yes 2>/dev/null || true; } | "$@" || status=$?
  return "$status"
}

# rc_note RC: a short human note for an exit code.
rc_note() {
  case "$1" in
    124|137) printf 'timed out after %ss' "${CBS_RUN_TIMEOUT:-$CBS_TIMEOUT}" ;;
    126) printf 'could not execute' ;;
    127) printf 'command not found' ;;
    *) printf 'exit code %s' "$1" ;;
  esac
}

# ---------------------------------------------------------------------------
# Temp files and the exit trap
# ---------------------------------------------------------------------------
tmp_cleanup() {
  local p
  for p in "${CBS_TMP_PATHS[@]-}"; do
    [ -n "$p" ] && rm -rf -- "$p"
  done
  CBS_TMP_PATHS=()
}

# cbs_exit_trap: remove temp files and, when a run log is still open (an
# early exit), close it with the exit status so the footer is never lost.
cbs_exit_trap() {
  local rc=$?
  tmp_cleanup
  if [ -n "${CBS_LOG_FILE:-}" ] && declare -F runlog_close >/dev/null; then
    runlog_close "$rc"
  fi
  return 0
}
# The test harness owns the EXIT trap and calls tmp_cleanup itself.
if [ "${CBS_SKIP_EXIT_TRAP:-0}" != 1 ]; then
  trap cbs_exit_trap EXIT
fi

# tmp_dir: prints a fresh temp dir that is removed at exit.
tmp_dir() {
  local d
  d=$(mktemp -d "${TMPDIR:-/tmp}/chromebrew-scripts.XXXXXX") || return 1
  CBS_TMP_PATHS+=("$d")
  printf '%s\n' "$d"
}

# tmp_file: prints a fresh temp file that is removed at exit.
tmp_file() {
  local f
  f=$(mktemp "${TMPDIR:-/tmp}/chromebrew-scripts.XXXXXX") || return 1
  CBS_TMP_PATHS+=("$f")
  printf '%s\n' "$f"
}

# ---------------------------------------------------------------------------
# Downloads
# ---------------------------------------------------------------------------
# download URL DEST: fetch over https with curl -f into DEST (a temp path).
# file:// is accepted only with CHROMEBREW_SCRIPTS_ALLOW_FILE_SOURCE=1 (tests).
download() {
  local url="$1" dest="$2"
  case "$url" in
    https://*) ;;
    file:///*) [ "${CHROMEBREW_SCRIPTS_ALLOW_FILE_SOURCE:-0}" = 1 ] || { log_error "refusing non-https download: $url"; return 1; } ;;
    *) log_error "refusing non-https download: $url"; return 1 ;;
  esac
  has_cmd curl || { log_error "curl is not installed; cannot download $url"; return 1; }
  log_cmd "curl -fsSL $url"
  # --proto-redir: a redirect may not downgrade to http (file: is the test hook).
  if ! curl -fsSL --proto '=https,file' --proto-redir '=https' \
      --retry 2 --connect-timeout 20 --max-time "$CBS_DOWNLOAD_TIMEOUT" \
      -o "$dest" "$url" </dev/null; then
    log_error "download failed: $url"
    rm -f -- "$dest"
    return 1
  fi
  [ -s "$dest" ] || { log_error "download produced an empty file: $url"; return 1; }
  return 0
}

# sha256_of FILE: prints the hex digest.
sha256_of() {
  if has_cmd sha256sum; then
    sha256sum "$1" | cut -d' ' -f1
  elif has_cmd shasum; then
    shasum -a 256 "$1" | cut -d' ' -f1
  else
    return 1
  fi
}

# verify_sha256 FILE EXPECTED: compare digests; EXPECTED may be a bare hash
# or a line like "<hash>  filename".
verify_sha256() {
  local file="$1" expected="$2" actual
  expected=${expected%%[[:space:]]*}
  expected=${expected,,}
  if ! [[ "$expected" =~ ^[0-9a-f]{64}$ ]]; then
    log_error "no valid sha256 checksum available for $(basename "$file")"
    return 1
  fi
  actual=$(sha256_of "$file") || { log_error "no sha256 tool available"; return 1; }
  if [ "$actual" != "$expected" ]; then
    log_error "checksum mismatch for $(basename "$file"): expected $expected got $actual"
    return 1
  fi
  log_detail "checksum ok: $expected"
  return 0
}

# ---------------------------------------------------------------------------
# Confirmation
# ---------------------------------------------------------------------------
# confirm QUESTION: ask "QUESTION [y/N]" on the console. Returns 0 only for
# a real y/Y. With --yes it is answered automatically; without --yes and
# without a terminal on stdin it refuses rather than guessing.
confirm() {
  local question="$1" reply=''
  if [ "$CBS_YES" = 1 ]; then
    log_info "confirmed by --yes: $question"
    return 0
  fi
  if [ ! -t 0 ]; then
    log_error "refusing to continue: stdin is not a terminal and --yes was not given ($question)"
    return 1
  fi
  printf '%s%s %s [y/N]:%s ' "$C_YELLOW" "$I_WARN" "$question" "$C_RESET" >&"$CBS_OUT"
  read -r -n1 reply || true
  printf '\n' >&"$CBS_OUT"
  _log_file "confirm: $question -> ${reply:-<none>}"
  case "$reply" in
    y|Y) return 0 ;;
    *)
      log_info "aborted; nothing was changed"
      return 1 ;;
  esac
}

# bool VALUE: true for 1/yes/true/on (case-insensitive).
bool() {
  case "${1,,}" in
    1|yes|true|on|y) return 0 ;;
    *) return 1 ;;
  esac
}

# human_mb MB: "1.5 GiB" / "512 MiB" for a size in MiB.
human_mb() {
  local mb="$1"
  if [ "$mb" -ge 1024 ] 2>/dev/null; then
    printf '%s.%s GiB' "$((mb / 1024))" "$(((mb % 1024) * 10 / 1024))"
  else
    printf '%s MiB' "$mb"
  fi
}
