#!/usr/bin/env bats
# tests/unit/runlog.bats - the per-run log file.

load ../test_helper

setup() { setup_sandbox; }

version() { tr -d '[:space:]' < "$REPO_ROOT/VERSION"; }

@test "every run writes a log with a header, the messages and a footer" {
  run env TIMEOUT=5 "$CBS_BIN_DIR/rw" -ny
  [ "$status" -eq 0 ]
  local f log
  f=$(log_files | tail -n1)
  [ -n "$f" ]
  [[ "$f" == "$LOG_DIR_DEFAULT"/[0-9]*-rw-*.log ]]
  assert_output_contains "  log: $f"
  log=$(cat "$f")
  assert_contains "$log" "# chromebrew-scripts $(version)"
  assert_contains "$log" "# started  "
  assert_contains "$log" "# host     $(uname -n) ("
  assert_contains "$log" "# os       ChromeOS"
  assert_contains "$log" "# user     $(id -un) (uid $(id -u))"
  assert_contains "$log" "# command  rw -ny"
  assert_contains "$log" "# program  $CBS_BIN_DIR/chromebrew-scripts"
  assert_contains "$log" "# mode     dry run"
  assert_contains "$log" "# setting  TIMEOUT=5 (env)"
  assert_contains "$log" "would run: sudo mount -o remount,rw $SANDBOX"
  assert_contains "$log" "Summary (dry run)"
  [[ "$log" =~ $'\n'[0-9]{2}:[0-9]{2}:[0-9]{2}\ .*would\ run ]]
  [[ "$log" =~ \#\ finished\ [0-9]{4}-[0-9]{2}-[0-9]{2}\ .*,\ exit\ status\ 0,\ [0-9]+s$ ]]
  if [ "$CBS_TEST_TARGET" = bundle ]; then
    assert_contains "$log" "(single file)"
  fi
}

@test "the header names the release and the board when lsb-release is readable" {
  write_lsb_release "Chrome OS" ltc-channel 16093.68.0
  run "$CBS_BIN_DIR/rw" -ny
  [ "$status" -eq 0 ]
  local f
  f=$(log_files | tail -n1)
  grep -q '^# os       Chrome OS 16093.68.0 (M130, ltc-channel)$' "$f"
  grep -q '^# board    octopus, Official Build (from lsb-release, informational)$' "$f"
}

@test "the log records each command, its output, exit status and duration" {
  run "$CBS_BIN_DIR/powerwash" -y --no-reboot
  [ "$status" -eq 0 ]
  local f
  f=$(log_files | tail -n1)
  grep -q '\$ echo clobber | sudo tee' "$f"
  grep -qx 'clobber' "$f"  # the command's own output, copied as is
  grep -q -- '-> exit 0 after [0-9]*s$' "$f"
  grep -q '^# mode     real run$' "$f"
  grep -q 'exit status 0, ' "$f"
  grep -q 'confirmed by --yes' "$f"
}

@test "a failed run logs the failure and exit status 1" {
  run env STUB_EXIT_sudo=1 "$CBS_BIN_DIR/rw" -y
  [ "$status" -eq 1 ]
  local f
  f=$(log_files | tail -n1)
  grep -q -- '-> exit 1 after' "$f"
  grep -q 'failed (exit code 1)' "$f"
  grep -q 'exit status 1, ' "$f"
  run "$CBS_BIN_DIR/rw" </dev/null
  [ "$status" -eq 1 ]
  f=$(log_files | tail -n1)
  grep -q 'refusing to continue: stdin is not a terminal' "$f"
}

@test "log files are private: 0600 in a 0700 directory, and latest.log points at the newest" {
  run "$CBS_BIN_DIR/rw" -ny
  [ "$status" -eq 0 ]
  local f
  f=$(log_files | tail -n1)
  [ "$(stat -c %a "$LOG_DIR_DEFAULT")" = 700 ]
  [ "$(stat -c %a "$f")" = 600 ]
  [ -L "$LOG_DIR_DEFAULT/latest.log" ]
  [ "$(readlink "$LOG_DIR_DEFAULT/latest.log")" = "$(basename "$f")" ]
  grep -q '^# command  rw -ny$' "$LOG_DIR_DEFAULT/latest.log"
}

@test "LOG_KEEP prunes old logs; 0 keeps all" {
  local i
  for i in 1 2 3; do
    run env LOG_KEEP=2 "$CBS_BIN_DIR/rw" -ny
    [ "$status" -eq 0 ]
  done
  [ "$(log_files | wc -l)" -eq 2 ]
  for i in 1 2 3; do
    run env LOG_KEEP=0 "$CBS_BIN_DIR/rw" -ny
    [ "$status" -eq 0 ]
  done
  [ "$(log_files | wc -l)" -eq 5 ]
}

@test "--no-log, LOGGING=0 and an unwritable directory disable logging without failing" {
  run "$CBS_BIN_DIR/rw" -ny --no-log
  [ "$status" -eq 0 ]
  assert_output_not_contains "  log: "
  [ -z "$(log_files)" ]
  run env LOGGING=0 "$CBS_BIN_DIR/rw" -ny
  [ "$status" -eq 0 ]
  [ -z "$(log_files)" ]
  run env LOG_DIR=/proc/chromebrew-scripts-test "$CBS_BIN_DIR/rw" -ny
  [ "$status" -eq 0 ]
  assert_output_contains "cannot create log directory /proc/chromebrew-scripts-test; this run is not logged"
  assert_output_contains "would run: sudo mount -o remount,rw"
  [ -z "$(log_files)" ]
}

@test "--log FILE and LOG_DIR choose where the log goes" {
  run "$CBS_BIN_DIR/rw" -ny --log "$BATS_TEST_TMPDIR/my.log"
  [ "$status" -eq 0 ]
  [ -f "$BATS_TEST_TMPDIR/my.log" ]
  grep -q "^# command  rw -ny --log $BATS_TEST_TMPDIR/my.log$" "$BATS_TEST_TMPDIR/my.log"
  assert_output_contains "  log: $BATS_TEST_TMPDIR/my.log"
  [ -z "$(log_files)" ]
  run env LOG_DIR="$BATS_TEST_TMPDIR/logs" "$CBS_BIN_DIR/rw" -ny
  [ "$status" -eq 0 ]
  ls "$BATS_TEST_TMPDIR/logs"/*-rw-*.log >/dev/null
  [ -L "$BATS_TEST_TMPDIR/logs/latest.log" ]
  [ -z "$(log_files)" ]
  cd "$BATS_TEST_TMPDIR"
  run "$CBS_BIN_DIR/rw" -ny --log relative.log
  [ "$status" -eq 0 ]
  [ -f "$BATS_TEST_TMPDIR/relative.log" ]
}

@test "--help, --version and usage errors write no log" {
  run "$CBS_BIN_DIR/rw" --help
  run "$CBS_BIN_DIR/rw" --version
  run "$CBS_BIN_DIR/rw" --bogus
  run "$CBS_BIN_DIR/chromebrew"
  run "$CBS_BIN_DIR/chromebrew-scripts" nonsense
  [ -z "$(log_files)" ]
}

@test "--quiet hides the status lines on the console but they are all in the log" {
  run "$CBS_BIN_DIR/rw" -nyq
  [ "$status" -eq 0 ]
  assert_output_not_contains "would run"
  assert_output_contains "Summary (dry run)"
  local f
  f=$(log_files | tail -n1)
  grep -q "would run: sudo mount -o remount,rw $SANDBOX" "$f"
  grep -q "confirmed by --yes" "$f"
}

@test "colours never reach the log file" {
  run env -u NO_COLOR "$CBS_BIN_DIR/rw" -ny --color always
  [ "$status" -eq 0 ]
  assert_output_contains $'\033['
  local f
  f=$(log_files | tail -n1)
  ! grep -q $'\033' "$f"
  grep -q "would run: sudo mount -o remount,rw" "$f"
}

@test "verbose-only lines are in the log even without --verbose" {
  run "$CBS_BIN_DIR/rw" -y
  [ "$status" -eq 0 ]
  assert_output_not_contains "\$ sudo mount"
  local f
  f=$(log_files | tail -n1)
  grep -q "\$ sudo mount -o remount,rw $SANDBOX" "$f"
}
