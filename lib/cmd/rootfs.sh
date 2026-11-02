#!/usr/bin/env bash
# lib/cmd/rootfs.sh - remove rootfs verification.
# Reference: https://www.chromium.org/chromium-os/developer-library/guides/device/developer-mode/
#   (sudo /usr/share/vboot/bin/make_dev_ssd.sh --remove_rootfs_verification;
#   recent releases ask for the kernel partition: --partitions N)

CBS_ROOTFS_REBOOT=1
CBS_ROOTFS_EXTRA=()

cmd_rootfs_usage() {
  cat <<EOF
Usage: rootfs [options] [-- make_dev_ssd.sh args...]

Remove rootfs verification with
  ${CBS_SUDO:+$CBS_SUDO }$CBS_VBOOT_BIN/make_dev_ssd.sh --remove_rootfs_verification
and reboot. The reboot only happens when make_dev_ssd.sh succeeded. Once
the root filesystem is writable the device will no longer pass verified
boot, even if nothing is changed; a powerwash restores it.

Anything after "--" is passed to make_dev_ssd.sh; recent ChromeOS versions
ask for the kernel partition, e.g.: rootfs -- --partitions 2

Options:
      --no-reboot         do not reboot afterwards

EOF
  args_common_usage
}

cmd_rootfs_options() { printf '%s\n' --no-reboot --; }

cmd_rootfs_parse() {
  CBS_ROOTFS_EXTRA=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --no-reboot) CBS_ROOTFS_REBOOT=0 ;;
      --)
        shift
        CBS_ROOTFS_EXTRA=("$@")
        break ;;
      *) log_error "unknown option: $1"; return 2 ;;
    esac
    shift
  done
  return 0
}

rootfs_step_remove() {
  local rc=0 state
  state=$(chromeos_rootfs_verification)
  [ "$state" = off ] && log_info "/proc/cmdline suggests rootfs verification is already removed; running make_dev_ssd.sh anyway"
  do_sudo "$CBS_VBOOT_BIN/make_dev_ssd.sh" --remove_rootfs_verification ${CBS_ROOTFS_EXTRA[@]+"${CBS_ROOTFS_EXTRA[@]}"} || rc=$?
  if [ "$rc" -ne 0 ]; then
    step_fail "make_dev_ssd.sh failed ($(rc_note "$rc")); not rebooting"
    return 1
  fi
  if [ "$CBS_DRY_RUN" = 1 ]; then
    step_dry "would run make_dev_ssd.sh --remove_rootfs_verification"
  else
    step_updated "rootfs verification removed; takes effect after a reboot"
  fi
}

rootfs_step_reboot() {
  local rc=0
  do_sudo reboot || rc=$?
  if [ "$rc" -ne 0 ]; then
    step_fail "reboot failed ($(rc_note "$rc")); reboot by hand to apply the change"
    return 1
  fi
  if [ "$CBS_DRY_RUN" = 1 ]; then step_dry "would reboot"; else step_ok "rebooting"; fi
}

cmd_rootfs_run() {
  require_chromeos || return 1
  confirm "Are you sure you want to remove rootfs verification?" || return 1
  run_step "remove rootfs verification" rootfs_step_remove || return 1
  if [ "$CBS_ROOTFS_REBOOT" = 1 ]; then
    run_step "reboot" rootfs_step_reboot || return 1
  else
    log_info "rootfs verification removed; reboot to apply it"
  fi
  return 0
}
