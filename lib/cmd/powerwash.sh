#!/usr/bin/env bash
# lib/cmd/powerwash.sh - reset a ChromeOS device to factory settings.
# References:
#   https://support.google.com/chromebook/answer/183084
#   https://neverware.zendesk.com/hc/en-us/articles/115000765287--Powerwash-via-the-cmd-line
#   (CloudReady, now ChromeOS Flex: the .update_available "clobber" method)

CBS_PW_REBOOT=1

cmd_powerwash_usage() {
  cat <<EOF
Usage: powerwash [options]

Reset this ChromeOS device to factory settings (powerwash). Writes "clobber"
to $CBS_STATEFUL/.update_available and reboots; every
local file and user account is erased on the next boot. Back up first
(chromebrew --backup saves the Chromebrew package list).

Options:
      --no-reboot         schedule the powerwash but do not reboot

EOF
  args_common_usage
}

cmd_powerwash_options() { printf '%s\n' --no-reboot; }

cmd_powerwash_parse() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --no-reboot) CBS_PW_REBOOT=0 ;;
      *) log_error "unknown option: $1"; return 2 ;;
    esac
    shift
  done
  return 0
}

# _pw_write_marker: echo clobber | sudo tee .update_available
_pw_write_marker() {
  local -a pfx=()
  # shellcheck disable=SC2206  # CBS_SUDO may hold a command with flags
  [ -n "$CBS_SUDO" ] && pfx=($CBS_SUDO)
  echo clobber | ${pfx[@]+"${pfx[@]}"} tee "$CBS_STATEFUL/.update_available"
}

pw_step_marker() {
  local rc=0
  do_pipe "echo clobber | ${CBS_SUDO:+$CBS_SUDO }tee $CBS_STATEFUL/.update_available" _pw_write_marker || rc=$?
  if [ "$rc" -ne 0 ]; then
    step_fail "could not write $CBS_STATEFUL/.update_available ($(rc_note "$rc")); not rebooting"
    return 1
  fi
  if [ "$CBS_DRY_RUN" = 1 ]; then
    step_dry "would write clobber to $CBS_STATEFUL/.update_available"
  else
    step_updated "powerwash scheduled for the next boot"
  fi
}

pw_step_reboot() {
  local rc=0
  do_sudo reboot || rc=$?
  if [ "$rc" -ne 0 ]; then
    step_fail "reboot failed ($(rc_note "$rc")); the powerwash runs on the next boot"
    return 1
  fi
  if [ "$CBS_DRY_RUN" = 1 ]; then step_dry "would reboot"; else step_ok "rebooting"; fi
}

cmd_powerwash_run() {
  require_chromeos || return 1
  confirm "Are you sure you want to reset this device to factory settings? Every local file and account will be erased." || return 1
  run_step "schedule the powerwash" pw_step_marker || return 1
  if [ "$CBS_PW_REBOOT" = 1 ]; then
    run_step "reboot" pw_step_reboot || return 1
  else
    log_info "powerwash scheduled; reboot to apply it"
  fi
  return 0
}
