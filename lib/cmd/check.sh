#!/usr/bin/env bash
# lib/cmd/check.sh - a read-only report on the device and this toolkit.
#
# Nothing here changes anything or needs sudo. Every probe degrades to
# "unknown" when its source is missing (see lib/core/chromeos.sh).

CBS_CHECK_OFFLINE=0

cmd_check_usage() {
  cat <<EOF
Usage: cbs-check [options]
       chromebrew-scripts check [options]

Show what the other commands depend on: ChromeOS release and channel,
developer mode, rootfs verification, how /, the stateful partition and the
user home are mounted, free space, Chromebrew, and whether this toolkit
is current. Read-only; never asks for sudo.

Probes: /etc/lsb-release (release, channel; the board is informational),
crossystem devsw_boot / cros_debug (developer mode and shell),
/proc/cmdline (dm-verity => rootfs verification on), /proc/mounts
(rw/ro, exec/noexec), df (free space), crew version, and for the toolkit a
network lookup of the newest release or commit (skipped with --offline).

Options:
      --offline           do not look up the newest toolkit version

EOF
  args_common_usage
}

cmd_check_options() { printf '%s\n' --offline; }

cmd_check_parse() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --offline) CBS_CHECK_OFFLINE=1 ;;
      *) log_error "unknown option: $1"; return 2 ;;
    esac
    shift
  done
  return 0
}

# _check_mount PATH FLAG_WANTED LABEL_YES LABEL_NO
_check_mount_rw() {
  local path="$1" v
  v=$(mount_has "$path" rw)
  case "$v" in
    yes) printf 'read/write (rw)' ;;
    no) printf 'read-only (ro)' ;;
    *) printf 'unknown (not found in %s)' "$CBS_PROC_MOUNTS" ;;
  esac
}

_check_mount_exec() {
  local path="$1" v
  v=$(mount_has "$path" noexec)
  case "$v" in
    yes) printf 'noexec (executables blocked)' ;;
    no) printf 'exec (executables allowed)' ;;
    *) printf 'unknown (not found in %s)' "$CBS_PROC_MOUNTS" ;;
  esac
}

# _check_toolkit_kind: how this toolkit is installed.
_check_toolkit_kind() {
  if [ "$CBS_BUNDLED" = 1 ]; then
    echo "single file"
  elif [ -e "$CBS_ROOT_DIR/.git" ]; then
    echo "git checkout"
  else
    echo "tree install"
  fi
}

# _check_toolkit_current: current / update available / unknown, from the
# published release checksum (single file) or the origin's HEAD (checkout).
_check_toolkit_current() {
  local repo tmp sum mine local_rev remote_rev
  repo=$(cfg SELF_UPDATE_REPO)
  if [ "$CBS_BUNDLED" = 1 ]; then
    tmp=$(tmp_dir) || { echo "unknown"; return 0; }
    # A failed fetch is an answer here, not an error: silence the console.
    if ! (exec {CBS_OUT}>/dev/null; CBS_DOWNLOAD_TIMEOUT=30 download "${repo%.git}/releases/latest/download/chromebrew-scripts.sha256" "$tmp/sum") 2>/dev/null; then
      echo "unknown (could not fetch the latest release checksum from $repo)"
      return 0
    fi
    sum=$(head -n1 "$tmp/sum"); sum="${sum%%[[:space:]]*}"; sum="${sum,,}"
    mine=$(sha256_of "$CBS_BIN") || { echo unknown; return 0; }
    if [ "$mine" = "$sum" ]; then echo "current (matches the latest release)"; else echo "update available: run --self-update"; fi
  elif [ -e "$CBS_ROOT_DIR/.git" ] && has_cmd git; then
    local origin
    origin=$(git -C "$CBS_ROOT_DIR" remote get-url origin 2>/dev/null) || origin=""
    [ "${CBS_CFG_SOURCE[SELF_UPDATE_REPO]:-default}" != default ] && origin="$repo"
    [ -n "$origin" ] || { echo "unknown (no origin remote)"; return 0; }
    local_rev=$(git -C "$CBS_ROOT_DIR" rev-parse HEAD 2>/dev/null) || { echo unknown; return 0; }
    remote_rev=$(timeout 30 git ls-remote "$origin" HEAD 2>/dev/null </dev/null | cut -f1 | head -n1)
    [ -n "$remote_rev" ] || { echo "unknown (could not reach $origin)"; return 0; }
    if [ "$remote_rev" = "$local_rev" ]; then echo "current (HEAD matches $origin)"; else echo "differs from $origin: run --self-update --dry-run"; fi
  else
    echo "unknown for a tree install: run --self-update --dry-run"
  fi
}

cmd_check_run() {
  local crew channel mb logdir
  if is_chromeos; then
    log_kv "ChromeOS" "yes: $(chromeos_describe)"
  else
    log_kv "ChromeOS" "no: $(chromeos_describe)"
  fi
  [ -n "$CBS_OS_DESCRIPTION" ] && log_kv "Release" "$CBS_OS_DESCRIPTION"
  channel=$(chromeos_channel)
  case "$channel" in
    unknown) log_kv "Release channel" "unknown" ;;
    stable|ltc|lts) log_kv "Release channel" "$channel (supported by the Chromebrew installer)" ;;
    *) log_kv "Release channel" "$channel (not supported by the Chromebrew installer: stable or ltc needed)" ;;
  esac
  log_kv "Board" "${CBS_OS_BOARD:-unknown}${CBS_OS_BOARD:+ (lsb-release, informational)}"
  log_kv "Developer mode" "$(chromeos_dev_mode) (crossystem devsw_boot)"
  log_kv "Developer shell" "$(chromeos_cros_debug) (crossystem cros_debug)"
  log_kv "Rootfs verification" "$(chromeos_rootfs_verification) (dm-verity in $CBS_PROC_CMDLINE)"
  log_kv "Crostini container" "$(is_crostini && echo yes || echo no)"
  log_kv "$CBS_ROOTFS_MOUNT mount" "$(_check_mount_rw "$CBS_ROOTFS_MOUNT")"
  log_kv "stateful mount" "$(_check_mount_exec "$CBS_STATEFUL")"
  log_kv "user home mount" "$(_check_mount_exec "$CBS_USER_HOME")"
  if mb=$(free_space_mb "$CBS_STATEFUL"); then
    log_kv "Free on stateful" "$(human_mb "$mb") ($CBS_STATEFUL)"
  else
    log_kv "Free on stateful" "unknown (df failed for $CBS_STATEFUL)"
  fi
  log_kv "Chromebrew prefix" "$CBS_CREW_PREFIX"
  if crew=$(crew_bin); then
    log_kv "crew" "$crew, version $(crew_version)"
  else
    log_kv "crew" "not installed"
  fi
  log_kv "Toolkit" "$(version_string), $(_check_toolkit_kind) at $(if [ "$CBS_BUNDLED" = 1 ]; then printf '%s' "$CBS_BIN"; else printf '%s' "$CBS_ROOT_DIR"; fi)"
  if [ "$CBS_CHECK_OFFLINE" = 1 ]; then
    log_kv "Toolkit update" "not checked (--offline)"
  else
    log_kv "Toolkit update" "$(_check_toolkit_current)"
  fi
  if cfg_bool LOGGING; then
    logdir=$(cfg LOG_DIR); [ -n "$logdir" ] || logdir=$(runlog_default_dir)
    log_kv "Logs" "$logdir (newest $(cfg LOG_KEEP) kept)"
  else
    log_kv "Logs" "off (LOGGING=0)"
  fi
  log_kv "Config" "$(config_user_file)$([ -r "$(config_user_file)" ] || printf ' (absent)'), $(config_system_file)$([ -r "$(config_system_file)" ] || printf ' (absent)')"
  local settings
  settings=$(config_print_nondefault '' | tr '\n' ' ')
  settings="${settings% }"
  log_kv "Settings (non-default)" "${settings:-(defaults)}"
  return 0
}
