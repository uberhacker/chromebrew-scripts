#!/usr/bin/env bats
# tests/unit/commands.bats - the entry point and the powerwash, rootfs and
# rw commands, through bin/ or a single-file build (CBS_TEST_TARGET).

load ../test_helper

setup() { setup_sandbox; }

@test "--version prints the version under every command name" {
  local cmd
  for cmd in chromebrew-scripts chromebrew powerwash rootfs rw cbs-check; do
    run "$CBS_BIN_DIR/$cmd" --version
    [ "$status" -eq 0 ]
    assert_version_output
  done
}

@test "--help shows a command's usage and the common options" {
  run "$CBS_BIN_DIR/rw" --help
  [ "$status" -eq 0 ]
  assert_output_contains "Usage: rw [options]"
  assert_output_contains "--undo"
  assert_output_contains "Common options (every command):"
  run "$CBS_BIN_DIR/chromebrew-scripts" powerwash -h
  [ "$status" -eq 0 ]
  assert_output_contains "Usage: powerwash [options]"
  run "$CBS_BIN_DIR/chromebrew-scripts" --help
  [ "$status" -eq 0 ]
  assert_output_contains "Usage: chromebrew-scripts COMMAND [options]"
  assert_output_contains "cbs-check"
}

@test "no command prints the toolkit usage; an unknown command fails with 2" {
  run "$CBS_BIN_DIR/chromebrew-scripts"
  [ "$status" -eq 0 ]
  assert_output_contains "Usage: chromebrew-scripts COMMAND"
  run "$CBS_BIN_DIR/chromebrew-scripts" frobnicate
  [ "$status" -eq 2 ]
  assert_output_contains "unknown command: frobnicate"
  [ -z "$(log_files)" ]
}

@test "an unknown option fails with 2, prints the usage on stderr and leaves no log" {
  run --separate-stderr "$CBS_BIN_DIR/rw" --bogus
  [ "$status" -eq 2 ]
  assert_contains "$output$stderr" "unknown option: --bogus"
  assert_contains "$stderr" "Usage: rw"
  [ -z "$(log_files)" ]
  [ -z "$(calls)" ]
  run "$CBS_BIN_DIR/rw" --timeout
  [ "$status" -eq 2 ]
  assert_output_contains "option --timeout requires a value"
}

@test "commands refuse to run off ChromeOS unless CBS_ASSUME_CHROMEOS=1" {
  unset CBS_ASSUME_CHROMEOS
  run "$CBS_BIN_DIR/rw" --yes
  [ "$status" -eq 1 ]
  assert_output_contains "only runs on ChromeOS"
  assert_not_called mount
  write_lsb_release
  run "$CBS_BIN_DIR/rw" --yes
  [ "$status" -eq 0 ]
  assert_called "mount -o remount,rw $SANDBOX"
}

@test "the header names the release read from lsb-release" {
  write_lsb_release "Chrome OS" stable-channel 16093.68.0
  run "$CBS_BIN_DIR/rw" -ny
  [ "$status" -eq 0 ]
  assert_output_contains " on Chrome OS 16093.68.0 (M130, stable-channel)"
}

@test "confirmation refuses on non-tty stdin without --yes" {
  local cmd
  for cmd in powerwash rootfs rw; do
    run "$CBS_BIN_DIR/$cmd" </dev/null
    [ "$status" -eq 1 ]
    assert_output_contains "stdin is not a terminal and --yes was not given"
  done
  [ -z "$(calls)" ]
  [ ! -e "$SANDBOX/mnt/stateful_partition/.update_available" ]
}

@test "confirmation accepts a real y and rejects anything else on a tty" {
  command -v script >/dev/null || skip "script(1) not available"
  # script(1) gives the command a pty and forwards our stdin into it.
  run bash -c "(printf n; sleep 1) | script -qec '$CBS_BIN_DIR/rw' /dev/null"
  assert_output_contains "aborted; nothing was changed"
  assert_not_called mount
  run bash -c "(printf y; sleep 1) | script -qec '$CBS_BIN_DIR/rw' /dev/null"
  assert_called "mount -o remount,rw $SANDBOX"
}

@test "-ny combines --dry-run and --yes: the plan is printed, nothing runs" {
  run "$CBS_BIN_DIR/rw" -ny
  [ "$status" -eq 0 ]
  assert_output_contains "dry run: nothing will be changed"
  assert_output_contains "confirmed by --yes: Are you sure you want to mount the filesystem read/write?"
  assert_output_contains "would run: sudo mount -o remount,rw $SANDBOX"
  assert_output_contains "would run: sudo mount -o remount,exec $SANDBOX/mnt/stateful_partition"
  assert_output_contains "would run: sudo mount -i -o remount,exec $SANDBOX/home/chronos/user"
  assert_output_contains "Summary (dry run)"
  assert_output_contains "0 ok, 0 updated, 0 skipped, 0 failed, 3 dry-run"
  [ -z "$(calls)" ]
}

@test "rw remounts / read/write and the stateful partition and home exec" {
  run "$CBS_BIN_DIR/rw" --yes
  [ "$status" -eq 0 ]
  assert_called "sudo mount -o remount,rw $SANDBOX"
  assert_called "mount -o remount,rw $SANDBOX"
  assert_called "mount -o remount,exec $SANDBOX/mnt/stateful_partition"
  assert_called "mount -i -o remount,exec $SANDBOX/home/chronos/user"
  assert_output_contains "remount $SANDBOX read/write: remounted rw"
  assert_output_contains "0 ok, 3 updated, 0 skipped, 0 failed, 0 dry-run"
  assert_output_contains "full read/write access"
}

@test "rw --undo remounts / read-only and the stateful partition and home noexec" {
  run "$CBS_BIN_DIR/rw" --undo -y
  [ "$status" -eq 0 ]
  assert_called "mount -o remount,ro $SANDBOX"
  assert_called "mount -o remount,noexec $SANDBOX/mnt/stateful_partition"
  assert_called "mount -i -o remount,noexec $SANDBOX/home/chronos/user"
  assert_not_called "remount,rw"
  assert_output_contains "read-only again"
  run "$CBS_BIN_DIR/rw" --ro -ny
  [ "$status" -eq 0 ]
  assert_output_contains "would run: sudo mount -o remount,ro $SANDBOX"
}

@test "rw skips a mount that is already in the wanted state" {
  write_mounts "rw,relatime" "rw,nosuid,nodev,noexec,relatime" "rw,nosuid,nodev,exec"
  run "$CBS_BIN_DIR/rw" -y
  [ "$status" -eq 0 ]
  assert_not_called "mount -o remount,rw $SANDBOX"
  assert_called "mount -o remount,exec $SANDBOX/mnt/stateful_partition"
  assert_not_called "mount -i -o remount,exec"
  assert_output_contains "already mounted rw"
  assert_output_contains "0 ok, 1 updated, 2 skipped, 0 failed, 0 dry-run"
  : > "$STUB_LOG"
  write_mounts "ro,relatime" "rw,noexec" "rw,noexec"
  run "$CBS_BIN_DIR/rw" --undo -y
  [ "$status" -eq 0 ]
  assert_output_contains "0 ok, 0 updated, 3 skipped, 0 failed, 0 dry-run"
  [ -z "$(calls)" ]
}

@test "a failing mount stops rw with exit 1 and a failed summary" {
  run env STUB_EXIT_sudo=1 "$CBS_BIN_DIR/rw" -y
  [ "$status" -eq 1 ]
  assert_output_contains "mount -o remount,rw $SANDBOX failed (exit code 1)"
  assert_output_contains "0 ok, 0 updated, 0 skipped, 1 failed, 0 dry-run"
  assert_not_called "mount -o remount,exec"
}

@test "--verbose shows the commands as they run" {
  run "$CBS_BIN_DIR/rw" -yv
  [ "$status" -eq 0 ]
  assert_output_contains "\$ sudo mount -o remount,rw $SANDBOX"
  run "$CBS_BIN_DIR/rw" -y
  [ "$status" -eq 0 ]
  assert_output_not_contains "\$ sudo mount"
}

@test "powerwash writes the clobber marker and reboots" {
  run "$CBS_BIN_DIR/powerwash" --yes
  [ "$status" -eq 0 ]
  [ "$(cat "$SANDBOX/mnt/stateful_partition/.update_available")" = clobber ]
  assert_called "sudo tee $SANDBOX/mnt/stateful_partition/.update_available"
  assert_called "sudo reboot"
  assert_called "reboot"
  assert_output_contains "powerwash scheduled for the next boot"
  assert_output_contains "1 ok, 1 updated, 0 skipped, 0 failed, 0 dry-run"
}

@test "powerwash --no-reboot only schedules; --dry-run changes nothing" {
  run "$CBS_BIN_DIR/powerwash" --yes --no-reboot
  [ "$status" -eq 0 ]
  [ -e "$SANDBOX/mnt/stateful_partition/.update_available" ]
  assert_not_called reboot
  assert_output_contains "reboot to apply it"
  rm -f "$SANDBOX/mnt/stateful_partition/.update_available"
  : > "$STUB_LOG"
  run "$CBS_BIN_DIR/powerwash" -ny
  [ "$status" -eq 0 ]
  assert_output_contains "would run: echo clobber | sudo tee $SANDBOX/mnt/stateful_partition/.update_available"
  assert_output_contains "would run: sudo reboot"
  [ ! -e "$SANDBOX/mnt/stateful_partition/.update_available" ]
  [ -z "$(calls)" ]
}

@test "powerwash does not reboot when the marker cannot be written" {
  run env STUB_EXIT_sudo=1 "$CBS_BIN_DIR/powerwash" -y
  [ "$status" -eq 1 ]
  assert_output_contains "could not write $SANDBOX/mnt/stateful_partition/.update_available"
  assert_output_contains "not rebooting"
  assert_not_called reboot
}

@test "rootfs runs make_dev_ssd.sh with the arguments after -- and reboots" {
  run "$CBS_BIN_DIR/rootfs" --yes -- --partitions 2
  [ "$status" -eq 0 ]
  assert_called "sudo $SANDBOX/usr/share/vboot/bin/make_dev_ssd.sh --remove_rootfs_verification --partitions 2"
  assert_called "make_dev_ssd.sh --remove_rootfs_verification --partitions 2"
  assert_called "sudo reboot"
  assert_output_contains "rootfs verification removed"
}

@test "rootfs --no-reboot, and no reboot after a failed make_dev_ssd.sh" {
  run "$CBS_BIN_DIR/rootfs" -y --no-reboot
  [ "$status" -eq 0 ]
  assert_called "make_dev_ssd.sh --remove_rootfs_verification"
  assert_not_called reboot
  assert_output_contains "reboot to apply it"
  : > "$STUB_LOG"
  run env STUB_EXIT_make_dev_ssd_sh=3 "$CBS_BIN_DIR/rootfs" -y
  [ "$status" -eq 1 ]
  assert_output_contains "make_dev_ssd.sh failed (exit code 3); not rebooting"
  assert_not_called reboot
}

@test "rootfs notes when /proc/cmdline already shows verification removed" {
  write_cmdline plain
  run "$CBS_BIN_DIR/rootfs" -ny
  [ "$status" -eq 0 ]
  assert_output_contains "already removed; running make_dev_ssd.sh anyway"
  write_cmdline verified
  run "$CBS_BIN_DIR/rootfs" -ny
  [ "$status" -eq 0 ]
  assert_output_not_contains "already removed"
}

@test "--quiet hides third-party output but keeps warnings and the summary" {
  run "$CBS_BIN_DIR/powerwash" -y --no-reboot
  [ "$status" -eq 0 ]
  assert_output_contains "clobber"
  run "$CBS_BIN_DIR/powerwash" -yq --no-reboot
  [ "$status" -eq 0 ]
  assert_output_not_contains "clobber"
  assert_output_contains "Summary"
  assert_output_contains "powerwash scheduled for the next boot"
  run env STUB_EXIT_sudo=1 "$CBS_BIN_DIR/rw" -yq
  [ "$status" -eq 1 ]
  assert_output_contains "failed (exit code 1)"
}
