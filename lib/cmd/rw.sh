#!/usr/bin/env bash
# lib/cmd/rw.sh - mount the root filesystem read/write (and back again).
# Reference: https://www.chromium.org/chromium-os/developer-library/guides/device/developer-mode/

CBS_RW_UNDO=0

cmd_rw_usage() {
  cat <<EOF
Usage: rw [options]
       rw --undo [options]

Remount the root filesystem read/write and allow executables on the
stateful partition and the user home:
  ${CBS_SUDO:+$CBS_SUDO }mount -o remount,rw $CBS_ROOTFS_MOUNT
  ${CBS_SUDO:+$CBS_SUDO }mount -o remount,exec $CBS_STATEFUL
  ${CBS_SUDO:+$CBS_SUDO }mount -i -o remount,exec $CBS_USER_HOME

Remounting / read/write requires rootfs verification to be removed first
(see: rootfs). A mount that is already in the wanted state is skipped.

Options:
      --undo, --ro        reverse it: remount / read-only and the stateful
                          partition and the user home noexec again

EOF
  args_common_usage
}

cmd_rw_options() { printf '%s\n' --undo --ro; }

cmd_rw_parse() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --undo|--ro) CBS_RW_UNDO=1 ;;
      *) log_error "unknown option: $1"; return 2 ;;
    esac
    shift
  done
  return 0
}

# _rw_remount PATH OPTION ALREADY_FLAG ALREADY_WANTED [mount flags...]:
# remount PATH with OPTION unless /proc/mounts already shows ALREADY_FLAG
# as ALREADY_WANTED (yes/no); extra mount flags (-i) go before -o.
_rw_remount() {
  local path="$1" opt="$2" flag="$3" want="$4" rc=0
  shift 4
  if [ "$(mount_has "$path" "$flag")" = "$want" ]; then
    step_skip "already mounted ${opt}"
    return 0
  fi
  do_sudo mount "$@" -o "remount,$opt" "$path" || rc=$?
  if [ "$rc" -ne 0 ]; then
    step_fail "mount -o remount,$opt $path failed ($(rc_note "$rc"))"
    return 1
  fi
  if [ "$CBS_DRY_RUN" = 1 ]; then
    step_dry "would remount $opt"
  else
    step_updated "remounted $opt"
  fi
}

rw_step_root()     { _rw_remount "$CBS_ROOTFS_MOUNT" rw rw yes; }
rw_step_stateful() { _rw_remount "$CBS_STATEFUL" exec noexec no; }
rw_step_home()     { _rw_remount "$CBS_USER_HOME" exec noexec no -i; }
rw_undo_root()     { _rw_remount "$CBS_ROOTFS_MOUNT" ro ro yes; }
rw_undo_stateful() { _rw_remount "$CBS_STATEFUL" noexec noexec yes; }
rw_undo_home()     { _rw_remount "$CBS_USER_HOME" noexec noexec yes -i; }

cmd_rw_run() {
  require_chromeos || return 1
  if [ "$CBS_RW_UNDO" = 1 ]; then
    confirm "Remount $CBS_ROOTFS_MOUNT read-only and $CBS_STATEFUL, $CBS_USER_HOME noexec again?" || return 1
    run_step "remount $CBS_ROOTFS_MOUNT read-only" rw_undo_root || return 1
    run_step "forbid executables on $CBS_STATEFUL" rw_undo_stateful || return 1
    run_step "forbid executables on $CBS_USER_HOME" rw_undo_home || return 1
    [ "$CBS_DRY_RUN" = 1 ] || log_info "the root filesystem is read-only again; executables on the stateful partition and the user home are blocked"
  else
    confirm "Are you sure you want to mount the filesystem read/write?" || return 1
    run_step "remount $CBS_ROOTFS_MOUNT read/write" rw_step_root || return 1
    run_step "allow executables on $CBS_STATEFUL" rw_step_stateful || return 1
    run_step "allow executables on $CBS_USER_HOME" rw_step_home || return 1
    [ "$CBS_DRY_RUN" = 1 ] || log_info "you should now have full read/write access (rw --undo reverses it)"
  fi
  return 0
}
