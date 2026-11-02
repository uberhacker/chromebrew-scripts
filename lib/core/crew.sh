#!/usr/bin/env bash
# lib/core/crew.sh - finding and asking Chromebrew's crew.
#
# CBS_CREW_PREFIX is the Chromebrew prefix (CREW_PREFIX, default /usr/local
# under CBS_ROOT); args_apply sets it from the CREW_PREFIX setting.

CBS_CREW_PREFIX="${CBS_CREW_PREFIX:-${CBS_ROOT}/usr/local}"

# crew_bin: print the path of crew, or fail when it is not installed.
crew_bin() {
  if command -v crew 2>/dev/null; then
    return 0
  fi
  if [ -x "$CBS_CREW_PREFIX/bin/crew" ]; then
    printf '%s\n' "$CBS_CREW_PREFIX/bin/crew"
    return 0
  fi
  return 1
}

# crew_timeout_prefix: the words that bound a crew command's run time.
crew_timeout_prefix() {
  if has_cmd timeout && [ "$CBS_CREW_TIMEOUT" != 0 ]; then
    printf 'timeout -k 10 %s' "$CBS_CREW_TIMEOUT"
  fi
}

# crew_version: the first line of `crew version`, or "unknown".
crew_version() {
  local crew v
  crew=$(crew_bin) || { echo unknown; return 1; }
  v=$(CBS_RUN_TIMEOUT=60 run "$crew" version 2>/dev/null | head -n1)
  v="${v//[^[:print:]]/}"
  printf '%s\n' "${v:-unknown}"
}

# strip_ansi: remove colour escapes from stdin.
strip_ansi() {
  local line esc=$'\033' re
  re="$esc"'\[[0-9;]*[A-Za-z]'
  while IFS= read -r line || [ -n "$line" ]; do
    while [[ "$line" == *"${esc}["* ]] && [[ "$line" =~ $re ]]; do
      line="${line//"${BASH_REMATCH[0]}"/}"
    done
    printf '%s\n' "$line"
  done
}

# crew_installed: the installed package names, one per line, sorted, from
# `crew list installed`. Colour codes are stripped and only the first word
# of each line that looks like a package name is kept. (The subcommand is
# the one documented by `crew help list`; it could not be verified against
# a live Chromebrew while this was written.)
crew_installed() {
  local crew line name
  crew=$(crew_bin) || return 1
  CBS_RUN_TIMEOUT="$CBS_CREW_TIMEOUT" run "$crew" list installed 2>/dev/null | strip_ansi |
    while IFS= read -r line || [ -n "$line" ]; do
      name="${line%%[[:space:]]*}"
      [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9_.+-]*$ ]] || continue
      printf '%s\n' "$name"
    done | sort -u
}
