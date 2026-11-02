#!/usr/bin/env bats
# tests/unit/check.bats - the read-only system check (cbs-check).

load ../test_helper

setup() { setup_sandbox; }

# kv LABEL: the value printed for LABEL in $output.
kv() {
  printf '%s\n' "$output" | sed -n "s|^  $1:[[:space:]]*||p" | head -n1
}

@test "cbs-check reports the release, channel and board from lsb-release, and runs off ChromeOS too" {
  write_lsb_release "Chrome OS" stable-channel 16093.68.0
  run "$CBS_BIN_DIR/cbs-check" --offline
  [ "$status" -eq 0 ]
  [ "$(kv ChromeOS)" = "yes: Chrome OS 16093.68.0 (M130, stable-channel)" ]
  [ "$(kv Release)" = "16093.68.0 (Official Build) stable-channel octopus" ]
  [ "$(kv "Release channel")" = "stable (supported by the Chromebrew installer)" ]
  [ "$(kv Board)" = "octopus (lsb-release, informational)" ]
  write_lsb_release "Chrome OS" dev-channel
  run "$CBS_BIN_DIR/cbs-check" --offline
  [ "$status" -eq 0 ]
  [ "$(kv "Release channel")" = "dev (not supported by the Chromebrew installer: stable or ltc needed)" ]
  rm "$SANDBOX/etc/lsb-release"
  unset CBS_ASSUME_CHROMEOS
  run "$CBS_BIN_DIR/cbs-check" --offline
  [ "$status" -eq 0 ]
  [[ "$(kv ChromeOS)" == "no: not ChromeOS ("* ]]
  [ "$(kv "Release channel")" = unknown ]
  [ "$(kv Board)" = unknown ]
  assert_not_called sudo
}

@test "cbs-check probes developer mode and the developer shell through crossystem" {
  run "$CBS_BIN_DIR/cbs-check" --offline
  [ "$status" -eq 0 ]
  [ "$(kv "Developer mode")" = "unknown (crossystem devsw_boot)" ]
  [ "$(kv "Developer shell")" = "unknown (crossystem cros_debug)" ]
  use_crossystem_stub
  run env STUB_CROSSYSTEM_devsw_boot=1 STUB_CROSSYSTEM_cros_debug=0 "$CBS_BIN_DIR/cbs-check" --offline
  [ "$status" -eq 0 ]
  [ "$(kv "Developer mode")" = "yes (crossystem devsw_boot)" ]
  [ "$(kv "Developer shell")" = "no (crossystem cros_debug)" ]
  assert_called "crossystem devsw_boot"
  assert_called "crossystem cros_debug"
  run env STUB_EXIT_crossystem=1 "$CBS_BIN_DIR/cbs-check" --offline
  [ "$status" -eq 0 ]
  [ "$(kv "Developer mode")" = "unknown (crossystem devsw_boot)" ]
}

@test "cbs-check reads rootfs verification from the kernel command line" {
  run "$CBS_BIN_DIR/cbs-check" --offline
  [ "$status" -eq 0 ]
  [ "$(kv "Rootfs verification")" = "unknown (dm-verity in $SANDBOX/proc/cmdline)" ]
  write_cmdline verified
  run "$CBS_BIN_DIR/cbs-check" --offline
  [ "$(kv "Rootfs verification")" = "on (dm-verity in $SANDBOX/proc/cmdline)" ]
  write_cmdline plain
  run "$CBS_BIN_DIR/cbs-check" --offline
  [ "$(kv "Rootfs verification")" = "off (dm-verity in $SANDBOX/proc/cmdline)" ]
}

@test "cbs-check reports how /, the stateful partition and the user home are mounted" {
  run "$CBS_BIN_DIR/cbs-check" --offline
  [ "$status" -eq 0 ]
  [ "$(kv "$SANDBOX mount")" = "unknown (not found in $SANDBOX/proc/mounts)" ]
  write_mounts "ro,relatime" "rw,nosuid,nodev,noexec,relatime" "rw,nosuid,nodev,exec"
  run "$CBS_BIN_DIR/cbs-check" --offline
  [ "$(kv "$SANDBOX mount")" = "read-only (ro)" ]
  [ "$(kv "stateful mount")" = "noexec (executables blocked)" ]
  [ "$(kv "user home mount")" = "exec (executables allowed)" ]
  write_mounts "rw,relatime" "rw,exec" "rw,noexec"
  run "$CBS_BIN_DIR/cbs-check" --offline
  [ "$(kv "$SANDBOX mount")" = "read/write (rw)" ]
  [ "$(kv "stateful mount")" = "exec (executables allowed)" ]
  [ "$(kv "user home mount")" = "noexec (executables blocked)" ]
}

@test "cbs-check reports Crostini, free space, Chromebrew, the toolkit and the logs" {
  run "$CBS_BIN_DIR/cbs-check" --offline
  [ "$status" -eq 0 ]
  [ "$(kv "Crostini container")" = no ]
  [[ "$(kv "Free on stateful")" =~ ^[0-9]+(\.[0-9])?\ (GiB|MiB)\ \("$SANDBOX"/mnt/stateful_partition\)$ ]]
  [ "$(kv "Chromebrew prefix")" = "$SANDBOX/usr/local" ]
  [ "$(kv crew)" = "$STUBS/crew, version 1.59.0" ]
  [ "$(kv "Toolkit update")" = "not checked (--offline)" ]
  if [ "$CBS_TEST_TARGET" = bundle ]; then
    [[ "$(kv Toolkit)" == "chromebrew-scripts "*", single file at $CBS_BIN_DIR/chromebrew-scripts" ]]
  else
    [[ "$(kv Toolkit)" == "chromebrew-scripts "*", git checkout at $REPO_ROOT" ]]
  fi
  [ "$(kv Logs)" = "$LOG_DIR_DEFAULT (newest 20 kept)" ]
  [ "$(kv Config)" = "$CBS_HOME/.config/chromebrew-scripts/config (absent), $CBS_SYSTEM_CONFIG (absent)" ]
  mkdir -p "$SANDBOX/opt/google/cros-containers"
  without_crew
  run env LOGGING=0 "$CBS_BIN_DIR/cbs-check" --offline
  [ "$status" -eq 0 ]
  [ "$(kv "Crostini container")" = yes ]
  [ "$(kv crew)" = "not installed" ]
  [ "$(kv Logs)" = "off (LOGGING=0)" ]
  [ "$(kv "Settings (non-default)")" = "LOGGING=0 (env)" ]
  assert_not_called sudo
}

@test "cbs-check compares a single file with the published release checksum" {
  local dir="$BATS_TEST_TMPDIR/sf" rel="$SANDBOX/rel" d
  build_bundle "$dir"
  d="$rel/releases/latest/download"
  export CHROMEBREW_SCRIPTS_ALLOW_FILE_SOURCE=1 SELF_UPDATE_REPO="file://$rel"
  run "$dir/cbs-check"
  [ "$status" -eq 0 ]
  [ "$(kv "Toolkit update")" = "unknown (could not fetch the latest release checksum from file://$rel)" ]
  assert_output_not_contains "download failed"
  mkdir -p "$d"
  (cd "$d" && sha256sum "$dir/chromebrew-scripts" > chromebrew-scripts.sha256)
  run "$dir/cbs-check"
  [ "$status" -eq 0 ]
  [ "$(kv "Toolkit update")" = "current (matches the latest release)" ]
  echo "0000000000000000000000000000000000000000000000000000000000000000  chromebrew-scripts" > "$d/chromebrew-scripts.sha256"
  run "$dir/cbs-check"
  [ "$status" -eq 0 ]
  [ "$(kv "Toolkit update")" = "update available: run --self-update" ]
  assert_not_called sudo
}

@test "cbs-check rejects unknown options and takes no action" {
  run "$CBS_BIN_DIR/cbs-check" --fix
  [ "$status" -eq 2 ]
  assert_output_contains "unknown option: --fix"
  run "$CBS_BIN_DIR/chromebrew-scripts" check --offline -y
  [ "$status" -eq 0 ]
  [ -z "$(grep -v '^crew ' "$STUB_LOG")" ]
}
