#!/usr/bin/env bash
# lib/core/chromeos.sh - ChromeOS detection and read-only probes.
#
# Everything here only reads: /etc/lsb-release, /proc/cmdline, /proc/mounts,
# df and crossystem (the firmware's developer switches). Each probe answers
# yes/no/unknown, or a value, so that the check command and the install
# pre-checks degrade gracefully where a source is missing (a container, a
# ChromeOS Flex machine without crossystem, a test sandbox).
#
# Relocation knobs (tests and CI): CBS_ROOT is prepended to every path, and
# each path can be set on its own: CBS_LSB_RELEASE, CBS_STATEFUL,
# CBS_VBOOT_BIN, CBS_USER_HOME, CBS_ROOTFS_MOUNT, CBS_PROC_MOUNTS,
# CBS_PROC_CMDLINE, CBS_CROSTINI_DIR, CBS_CROSSYSTEM (the crossystem
# command). CBS_ASSUME_CHROMEOS=1 skips the detection.

CBS_LSB_RELEASE="${CBS_LSB_RELEASE:-${CBS_ROOT}/etc/lsb-release}"
CBS_STATEFUL="${CBS_STATEFUL:-${CBS_ROOT}/mnt/stateful_partition}"
CBS_VBOOT_BIN="${CBS_VBOOT_BIN:-${CBS_ROOT}/usr/share/vboot/bin}"
CBS_USER_HOME="${CBS_USER_HOME:-${CBS_ROOT}/home/chronos/user}"
CBS_ROOTFS_MOUNT="${CBS_ROOTFS_MOUNT:-${CBS_ROOT:-/}}"
CBS_PROC_MOUNTS="${CBS_PROC_MOUNTS:-${CBS_ROOT}/proc/mounts}"
CBS_PROC_CMDLINE="${CBS_PROC_CMDLINE:-${CBS_ROOT}/proc/cmdline}"
CBS_CROSTINI_DIR="${CBS_CROSTINI_DIR:-${CBS_ROOT}/opt/google/cros-containers}"
CBS_CROSSYSTEM="${CBS_CROSSYSTEM:-crossystem}"

CBS_OS_NAME=""
CBS_OS_DESCRIPTION=""
CBS_OS_VERSION=""
CBS_OS_MILESTONE=""
CBS_OS_TRACK=""
CBS_OS_BOARD=""
CBS_OS_BUILD_TYPE=""
CBS_IS_CHROMEOS=0

# lsb_value KEY [FILE]: the value of KEY in /etc/lsb-release, read line by
# line (never sourced). Format: KEY=value, one per line, optional quotes.
# https://www.chromium.org/chromium-os/developer-library/reference/infrastructure/lsb-release/
lsb_value() {
  local key="$1" file="${2:-$CBS_LSB_RELEASE}" line k v
  [ -r "$file" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    [[ "$line" =~ ^[[:space:]]*([A-Za-z0-9_]+)[[:space:]]*=(.*)$ ]] || continue
    k="${BASH_REMATCH[1]}"
    v="${BASH_REMATCH[2]}"
    [ "$k" = "$key" ] || continue
    v="${v#"${v%%[![:space:]]*}"}"
    v="${v%"${v##*[![:space:]]}"}"
    if [[ "$v" =~ ^\"(.*)\"$ ]]; then v="${BASH_REMATCH[1]}"; fi
    v="${v//[^[:print:]]/}"
    printf '%s\n' "$v"
    return 0
  done < "$file"
  return 1
}

# chromeos_detect: read the release file once.
chromeos_detect() {
  CBS_OS_NAME=$(lsb_value CHROMEOS_RELEASE_NAME) || CBS_OS_NAME=""
  CBS_OS_DESCRIPTION=$(lsb_value CHROMEOS_RELEASE_DESCRIPTION) || CBS_OS_DESCRIPTION=""
  CBS_OS_VERSION=$(lsb_value CHROMEOS_RELEASE_VERSION) || CBS_OS_VERSION=""
  CBS_OS_MILESTONE=$(lsb_value CHROMEOS_RELEASE_CHROME_MILESTONE) || CBS_OS_MILESTONE=""
  CBS_OS_TRACK=$(lsb_value CHROMEOS_RELEASE_TRACK) || CBS_OS_TRACK=""
  # The developer library says not to rely on CHROMEOS_RELEASE_BOARD from
  # this file; it is shown as informational only.
  CBS_OS_BOARD=$(lsb_value CHROMEOS_RELEASE_BOARD) || CBS_OS_BOARD=""
  CBS_OS_BUILD_TYPE=$(lsb_value CHROMEOS_RELEASE_BUILD_TYPE) || CBS_OS_BUILD_TYPE=""
  if [ "${CBS_ASSUME_CHROMEOS:-0}" = 1 ] || [ -n "$CBS_OS_NAME" ]; then
    CBS_IS_CHROMEOS=1
  else
    CBS_IS_CHROMEOS=0
  fi
}

is_chromeos() { [ "$CBS_IS_CHROMEOS" = 1 ]; }

# require_chromeos: fail (with a message) off ChromeOS.
require_chromeos() {
  is_chromeos && return 0
  log_error "this command only runs on ChromeOS / ChromiumOS (no CHROMEOS_RELEASE_NAME in $CBS_LSB_RELEASE)"
  log_info "set CBS_ASSUME_CHROMEOS=1 to override (tests and CI only)"
  return 1
}

# chromeos_channel: stable, beta, dev, canary, ltc, lts, ... or unknown.
chromeos_channel() {
  local track="$CBS_OS_TRACK"
  if [ -z "$track" ]; then
    echo unknown
  else
    printf '%s\n' "${track%-channel}"
  fi
}

# chromeos_channel_supported: Chromebrew's installer supports the stable
# and the long-term (ltc/lts) channels; beta, dev and canary are rejected.
chromeos_channel_supported() {
  case "$(chromeos_channel)" in
    stable|ltc|lts) return 0 ;;
    *) return 1 ;;
  esac
}

# chromeos_describe: one line for headers and the log.
chromeos_describe() {
  local s
  if ! is_chromeos; then
    printf 'not ChromeOS (%s)\n' "$(uname -sr 2>/dev/null || echo unknown)"
    return 0
  fi
  s="${CBS_OS_NAME:-ChromeOS}${CBS_OS_VERSION:+ $CBS_OS_VERSION}"
  if [ -n "$CBS_OS_MILESTONE" ] || [ -n "$CBS_OS_TRACK" ]; then
    s+=" (${CBS_OS_MILESTONE:+M$CBS_OS_MILESTONE}${CBS_OS_MILESTONE:+${CBS_OS_TRACK:+, }}${CBS_OS_TRACK})"
  fi
  printf '%s\n' "$s"
}

# is_crostini: inside a Crostini (Linux development environment) container.
is_crostini() { [ -d "$CBS_CROSTINI_DIR" ]; }

# chromeos_crossystem FLAG: the value of a crossystem flag, or failure when
# crossystem is missing or cannot answer (a container, some Flex machines).
chromeos_crossystem() {
  local out
  has_cmd "$CBS_CROSSYSTEM" || return 1
  if has_cmd timeout; then
    out=$(timeout 10 "$CBS_CROSSYSTEM" "$1" 2>/dev/null </dev/null) || return 1
  else
    out=$("$CBS_CROSSYSTEM" "$1" 2>/dev/null </dev/null) || return 1
  fi
  printf '%s\n' "${out//[^[:print:]]/}"
}

# _yes_no_flag FLAG: yes/no/unknown for a 1/0 crossystem flag.
_yes_no_flag() {
  local v
  v=$(chromeos_crossystem "$1") || { echo unknown; return 0; }
  case "$v" in
    1) echo yes ;;
    0) echo no ;;
    *) echo unknown ;;
  esac
}

# chromeos_dev_mode: was the device booted in developer mode (devsw_boot)?
chromeos_dev_mode() { _yes_no_flag devsw_boot; }

# chromeos_cros_debug: is the developer shell enabled (cros_debug)?
chromeos_cros_debug() { _yes_no_flag cros_debug; }

# chromeos_rootfs_verification: on/off/unknown. A verified root filesystem
# is mounted through dm-verity: the kernel command line then carries
# dm="... verity ..." and root=/dev/dm-0. make_dev_ssd.sh
# --remove_rootfs_verification rewrites it to a plain root=PARTUUID=...
chromeos_rootfs_verification() {
  local cmdline=""
  [ -r "$CBS_PROC_CMDLINE" ] || { echo unknown; return 0; }
  read -r cmdline < "$CBS_PROC_CMDLINE" || cmdline=""
  cmdline=" $cmdline"
  if [[ "$cmdline" == *" root=/dev/dm-0"* ]] || [[ "$cmdline" == *" dm="* ]]; then
    echo on
  elif [[ "$cmdline" == *" root="* ]]; then
    echo off
  else
    echo unknown
  fi
}

# mount_options PATH: the options of the filesystem mounted at PATH, from
# /proc/mounts (the last entry wins). Fails when PATH is not a mount point.
mount_options() {
  local path="$1" dev mnt type opts rest found=""
  [ -r "$CBS_PROC_MOUNTS" ] || return 1
  while read -r dev mnt type opts rest; do
    [ "$mnt" = "$path" ] && found="$opts"
  done < "$CBS_PROC_MOUNTS"
  : "$dev" "$type" "$rest"
  [ -n "$found" ] || return 1
  printf '%s\n' "$found"
}

# mount_has PATH OPTION: yes/no/unknown - is OPTION (rw, ro, exec, noexec,
# ...) among the mount options of PATH?
mount_has() {
  local opts
  opts=$(mount_options "$1") || { echo unknown; return 0; }
  case ",$opts," in
    *",$2,"*) echo yes ;;
    *) echo no ;;
  esac
}

# free_space_mb PATH: MiB available on PATH's filesystem (df -Pk), or failure.
free_space_mb() {
  local out kb _skip
  out=$(df -Pk -- "$1" 2>/dev/null) || return 1
  { read -r _skip; read -r _skip _skip _skip kb _skip; } <<< "$out"
  [[ "${kb:-}" =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "$((kb / 1024))"
}
