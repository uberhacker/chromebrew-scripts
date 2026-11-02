#!/usr/bin/env bash
# lib/core/log.sh - colours, icons and console output.
#
# Output conventions:
#   * Everything the toolkit itself says goes to the "console" descriptor
#     (CBS_OUT), a copy of the original stdout. --quiet silences third-party
#     output by redirecting fd 1 and 2 while our own status lines, warnings
#     and the summary still reach the terminal.
#   * Colours are used only when the console is a TTY, NO_COLOR is unset and
#     --no-color was not given (COLOR=always forces them on).
#   * Icons are Unicode when the locale is UTF-8, plain ASCII otherwise.
#   * With a run log open (CBS_LOG_FILE, see lib/core/runlog.sh) every line is
#     also appended there, timestamped and without colours, including what
#     --quiet hides and the verbose-only lines (commands, details). The log
#     is written by path, never through a kept-open descriptor: the commands
#     this toolkit runs (crew, the Chromebrew installer, mount) would inherit
#     such a descriptor.

: "${CBS_VERBOSE:=0}"
: "${CBS_QUIET:=0}"
: "${CBS_COLOR:=auto}"   # auto|always|never
CBS_USE_COLOR=0
CBS_USE_UTF8=0

# Duplicate stdout once so later redirections of fd 1 do not hide our output.
if [ -z "${CBS_OUT:-}" ]; then
  exec {CBS_OUT}>&1
fi

# log_color_enabled: should colours be used?
log_color_enabled() {
  case "${CBS_COLOR}" in
    always) return 0 ;;
    never) return 1 ;;
  esac
  [ -n "${NO_COLOR:-}" ] && return 1
  [ "${TERM:-}" = "dumb" ] && return 1
  # -t tests the *console* fd, which mirrors the original stdout.
  [ -t "$CBS_OUT" ] || return 1
  return 0
}

# log_utf8_enabled: can the locale show the Unicode status icons?
log_utf8_enabled() {
  local loc="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}"
  case "${loc,,}" in
    *utf-8*|*utf8*) return 0 ;;
    *) return 1 ;;
  esac
}

# log_init: (re)compute colour/icon settings. Called again after argument
# parsing (args_apply).
log_init() {
  if log_color_enabled; then CBS_USE_COLOR=1; else CBS_USE_COLOR=0; fi
  if log_utf8_enabled; then CBS_USE_UTF8=1; else CBS_USE_UTF8=0; fi

  if [ "$CBS_USE_COLOR" = 1 ]; then
    C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
    C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
    C_BLUE=$'\033[34m'; C_MAGENTA=$'\033[35m'; C_CYAN=$'\033[36m'
  else
    C_RESET=''; C_BOLD=''; C_DIM=''
    C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_MAGENTA=''; C_CYAN=''
  fi

  if [ "$CBS_USE_UTF8" = 1 ]; then
    I_STEP='▶'; I_OK='✔'; I_UPDATED='↑'; I_SKIPPED='–'
    I_FAILED='✖'; I_WARN='⚠'; I_DRY='◦'; I_INFO='·'
  else
    I_STEP='>'; I_OK='OK'; I_UPDATED='UP'; I_SKIPPED='--'
    I_FAILED='XX'; I_WARN='!!'; I_DRY='..'; I_INFO='-'
  fi
}

CBS_LOG_FILE="${CBS_LOG_FILE:-}"

# _log_file TEXT: append TEXT to the run log, if one is open: a timestamp,
# then the text with colour escapes removed.
_log_file() {
  [ -n "$CBS_LOG_FILE" ] || return 0
  local s="$*" esc=$'\033' re
  re="$esc"'\[[0-9;]*m'
  while [[ "$s" == *"${esc}["* ]] && [[ "$s" =~ $re ]]; do
    s="${s//"${BASH_REMATCH[0]}"/}"
  done
  if [ -z "$s" ]; then
    printf '\n' >> "$CBS_LOG_FILE"
  else
    printf '%(%H:%M:%S)T %s\n' -1 "$s" >> "$CBS_LOG_FILE"
  fi
}

# Low level writers: the console fd and the run log.
_log_write() {
  printf '%s\n' "$*" >&"$CBS_OUT"
  _log_file "$*"
}

# _log_quiet TEXT: the console unless --quiet; the run log always.
_log_quiet() {
  if [ "$CBS_QUIET" = 1 ]; then _log_file "$*"; else _log_write "$*"; fi
}

# _log_verbose TEXT: the console only with --verbose; the run log always.
_log_verbose() {
  if [ "$CBS_VERBOSE" = 1 ]; then _log_write "$*"; else _log_file "$*"; fi
}

# log_step TEXT: a step heading.
log_step() {
  _log_quiet ""
  _log_quiet "${C_BOLD}${C_BLUE}${I_STEP}${C_RESET} ${C_BOLD}$*${C_RESET}"
}

log_info() {
  _log_quiet "  ${C_DIM}${I_INFO}${C_RESET} $*"
}

# log_detail TEXT: verbose-only chatter.
log_detail() {
  _log_verbose "  ${C_DIM}  $*${C_RESET}"
}

# log_warn / log_error: always shown, --quiet or not.
log_warn() {
  _log_write "  ${C_YELLOW}${I_WARN} $*${C_RESET}"
}

log_error() {
  _log_write "  ${C_RED}${I_FAILED} $*${C_RESET}"
}

log_ok() {
  _log_quiet "  ${C_GREEN}${I_OK}${C_RESET} $*"
}

log_updated() {
  _log_quiet "  ${C_CYAN}${I_UPDATED}${C_RESET} $*"
}

log_skipped() {
  _log_quiet "  ${C_DIM}${I_SKIPPED} $*${C_RESET}"
}

log_dry() {
  _log_quiet "  ${C_MAGENTA}${I_DRY}${C_RESET} $*"
}

# log_cmd "cmd args": shown in verbose mode before a command runs (and
# always written to the run log).
log_cmd() {
  _log_verbose "  ${C_DIM}\$ $*${C_RESET}"
}

# log_plain TEXT: always printed (summary, --version, reports).
log_plain() {
  _log_write "$*"
}

# log_kv LABEL VALUE: an aligned "label:  value" report line.
log_kv() {
  _log_write "$(printf '  %-22s %s' "$1:" "$2")"
}

# Initialise with defaults so the functions are usable before args parsing.
log_init
