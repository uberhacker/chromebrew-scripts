#!/usr/bin/env bats
# tests/unit/chromebrew.bats - the chromebrew command: status, update,
# install with its pre-flight checks, remove, backup and restore.

load ../test_helper

setup() { setup_sandbox; }

@test "chromebrew needs exactly one action" {
  run "$CBS_BIN_DIR/chromebrew"
  [ "$status" -eq 2 ]
  assert_output_contains "choose an action"
  run "$CBS_BIN_DIR/chromebrew" -i -r
  [ "$status" -eq 2 ]
  assert_output_contains "choose exactly one action (got: install remove)"
  run "$CBS_BIN_DIR/chromebrew" --restore
  [ "$status" -eq 2 ]
  assert_output_contains "--restore needs the file"
  [ -z "$(log_files)" ]
}

@test "--status reports crew, the prefix and the ChromeOS detection" {
  run "$CBS_BIN_DIR/chromebrew" --status
  [ "$status" -eq 0 ]
  [[ "$output" =~ crew\ version:[[:space:]]+1\.59\.0 ]]
  [[ "$output" =~ Chromebrew\ prefix:[[:space:]]+"$SANDBOX"/usr/local ]]
  assert_output_contains "ChromeOS detected:"
  assert_called "crew version"
  without_crew
  run "$CBS_BIN_DIR/chromebrew" -s
  [ "$status" -eq 0 ]
  [[ "$output" =~ crew:[[:space:]]+not\ installed ]]
}

@test "--update runs crew update, then yes | crew upgrade, under CREW_TIMEOUT" {
  run "$CBS_BIN_DIR/chromebrew" --update -v
  [ "$status" -eq 0 ]
  assert_called "crew update"
  assert_called "crew upgrade"
  assert_output_contains "\$ timeout -k 10 3600 crew update"
  assert_output_contains "\$ yes | timeout -k 10 3600 crew upgrade"
  assert_output_contains "packages upgraded"
  : > "$STUB_LOG"
  run env CREW_TIMEOUT=10 "$CBS_BIN_DIR/chromebrew" -u -n
  [ "$status" -eq 0 ]
  assert_output_contains "would run: timeout -k 10 10 crew update"
  assert_output_contains "would run: yes | timeout -k 10 10 crew upgrade"
  [ -z "$(calls)" ]
}

@test "--update fails cleanly when crew is missing or fails" {
  without_crew
  run "$CBS_BIN_DIR/chromebrew" -u
  [ "$status" -eq 1 ]
  assert_output_contains "chromebrew is not installed"
  run env STUB_EXIT_crew=2 "$CBS_BIN_DIR/chromebrew" -u
  [ "$status" -eq 1 ]
}

@test "--install refuses when Chromebrew is already installed" {
  run "$CBS_BIN_DIR/chromebrew" -i
  [ "$status" -eq 1 ]
  assert_output_contains "chromebrew is currently installed"
  assert_not_called curl
}

@test "--install refuses to run as root" {
  [ "$(id -u)" -eq 0 ] || skip "not running as root"
  without_crew
  run "$CBS_BIN_DIR/chromebrew" -i
  [ "$status" -eq 1 ]
  assert_output_contains "must not be installed as root"
  assert_not_called curl
}

@test "--install downloads the installer and runs it, answering yes" {
  without_crew
  write_lsb_release
  export MIN_FREE_MB=1
  run_as_user "$CBS_BIN_DIR/chromebrew" --install
  [ "$status" -eq 0 ]
  assert_output_contains "pre-flight checks: channel stable,"
  assert_called "curl -fsSL --proto =https,file --proto-redir =https --retry 2 --connect-timeout 20 --max-time 300 -o"
  assert_called "https://raw.githubusercontent.com/chromebrew/chromebrew/master/install.sh"
  assert_called "installer euid=$EXPECT_UID answer=y force= args="
  assert_output_contains "Chromebrew installed; run: source $CBS_HOME/.bashrc"
  assert_output_contains "2 ok, 1 updated, 0 skipped, 0 failed, 0 dry-run"
}

@test "--install honours CREW_INSTALLER_URL and --dry-run, and reports an installer failure" {
  without_crew
  export MIN_FREE_MB=1 CREW_INSTALLER_URL=https://example.test/i.sh
  run_as_user "$CBS_BIN_DIR/chromebrew" -i -n
  [ "$status" -eq 0 ]
  assert_output_contains "would download https://example.test/i.sh"
  assert_output_contains "would run: yes | timeout -k 10 3600 bash install.sh"
  [ -z "$(calls)" ]
  export STUB_INSTALLER_EXIT=7
  run_as_user "$CBS_BIN_DIR/chromebrew" -i
  [ "$status" -eq 1 ]
  assert_called "https://example.test/i.sh"
  assert_output_contains "the Chromebrew installer failed (exit code 7)"
}

@test "--install pre-flight checks refuse Crostini, a beta channel and low free space" {
  without_crew
  export MIN_FREE_MB=1
  mkdir -p "$SANDBOX/opt/google/cros-containers"
  run_as_user "$CBS_BIN_DIR/chromebrew" -i
  [ "$status" -eq 1 ]
  assert_output_contains "this is a Crostini container"
  assert_output_contains "1 check(s) failed; pass --force"
  assert_not_called curl
  rmdir "$SANDBOX/opt/google/cros-containers"
  write_lsb_release "Chrome OS" beta-channel
  run_as_user "$CBS_BIN_DIR/chromebrew" -i
  [ "$status" -eq 1 ]
  assert_output_contains "the beta channel is not supported by the Chromebrew installer"
  write_lsb_release
  export MIN_FREE_MB=999999999
  run_as_user "$CBS_BIN_DIR/chromebrew" -i
  [ "$status" -eq 1 ]
  assert_output_contains "free on $SANDBOX/mnt/stateful_partition (MIN_FREE_MB=999999999)"
  assert_not_called curl
}

@test "--force or CREW_FORCE_INSTALL=1 overrides the checks and is passed to the installer" {
  without_crew
  export MIN_FREE_MB=999999999
  run_as_user "$CBS_BIN_DIR/chromebrew" -i --force
  [ "$status" -eq 0 ]
  assert_output_contains "continuing anyway (--force / CREW_FORCE_INSTALL=1)"
  assert_output_contains "1 check(s) overridden by --force"
  assert_called "installer euid=$EXPECT_UID answer=y force=1"
  : > "$STUB_LOG"
  export CREW_FORCE_INSTALL=1
  run_as_user "$CBS_BIN_DIR/chromebrew" -i -n
  [ "$status" -eq 0 ]
  assert_output_contains "would run: yes | env CREW_FORCE_INSTALL=1 timeout -k 10 3600 bash install.sh"
}

@test "--remove needs confirmation and refuses an unsafe or missing prefix" {
  run "$CBS_BIN_DIR/chromebrew" -r </dev/null
  [ "$status" -eq 1 ]
  assert_output_contains "stdin is not a terminal"
  run env CREW_PREFIX=/usr "$CBS_BIN_DIR/chromebrew" -r -y
  [ "$status" -eq 1 ]
  assert_output_contains "refusing to clear '/usr': not a safe Chromebrew prefix"
  run env CREW_PREFIX="$SANDBOX/nope" "$CBS_BIN_DIR/chromebrew" -r -y
  [ "$status" -eq 1 ]
  assert_output_contains "not an existing absolute directory"
  [ -z "$(grep -v '^crew ' "$STUB_LOG")" ]
}

@test "--remove clears the prefix but keeps this toolkit, and strips .bashrc with a backup" {
  local prefix="$SANDBOX/usr/local"
  mkdir -p "$prefix/bin" "$prefix/lib/crew" "$prefix/etc"
  echo data > "$prefix/bin/crew"
  echo data > "$prefix/lib/crew/x"
  echo data > "$prefix/etc/profile"
  ln -s "$CBS_BIN_DIR/rw" "$prefix/bin/rw"
  printf '%s\n' '# mine' 'source /usr/local/etc/profile' '# DO NOT DELETE THIS LINE' \
    '# See /usr/local/etc/profile for further details' 'export KEEP=1' > "$CBS_HOME/.bashrc"
  run "$CBS_BIN_DIR/chromebrew" --remove --dry-run --yes
  [ "$status" -eq 0 ]
  assert_output_contains "would clear $prefix/* (keeping"
  [ -e "$prefix/bin/crew" ]
  [ "$(wc -l < "$CBS_HOME/.bashrc")" -eq 5 ]
  run "$CBS_BIN_DIR/chromebrew" --remove --yes
  [ "$status" -eq 0 ]
  [ ! -e "$prefix/bin/crew" ]
  [ ! -e "$prefix/lib" ]
  [ ! -e "$prefix/etc" ]
  [ -L "$prefix/bin/rw" ]
  assert_output_contains "keeping $prefix/bin/rw"
  [ "$(cat "$CBS_HOME/.bashrc")" = $'# mine\nexport KEEP=1' ]
  ls "$CBS_HOME"/.bashrc.chromebrew-scripts.*.bak >/dev/null
  assert_output_contains "Chromebrew lines removed; backup at $CBS_HOME/.bashrc.chromebrew-scripts."
  assert_output_contains "$prefix/* cleared (kept"
  assert_output_contains "open a new shell"
}

@test "--backup writes the installed package list with a header" {
  run "$CBS_BIN_DIR/chromebrew" --backup "$BATS_TEST_TMPDIR/pkgs.txt"
  [ "$status" -eq 0 ]
  assert_called "crew list installed"
  assert_output_contains "3 package(s) saved to $BATS_TEST_TMPDIR/pkgs.txt"
  assert_output_contains "copy $BATS_TEST_TMPDIR/pkgs.txt to Google Drive"
  [ "$(grep -v '^#' "$BATS_TEST_TMPDIR/pkgs.txt")" = $'gcc_lib\npython3\nvim' ]
  grep -q '^# chromebrew-scripts package list (chromebrew-scripts ' "$BATS_TEST_TMPDIR/pkgs.txt"
  grep -q '^# crew     1.59.0 (' "$BATS_TEST_TMPDIR/pkgs.txt"
  grep -q "^# restore  chromebrew --restore $BATS_TEST_TMPDIR/pkgs.txt" "$BATS_TEST_TMPDIR/pkgs.txt"
  ! grep -q $'\033' "$BATS_TEST_TMPDIR/pkgs.txt"
}

@test "--backup goes to Downloads, else the config directory; BACKUP_DIR wins" {
  run "$CBS_BIN_DIR/chromebrew" -b
  [ "$status" -eq 0 ]
  ls "$CBS_HOME/.config/chromebrew-scripts/backups"/chromebrew-packages-*.txt >/dev/null
  mkdir -p "$CBS_HOME/MyFiles/Downloads"
  run "$CBS_BIN_DIR/chromebrew" -b
  [ "$status" -eq 0 ]
  ls "$CBS_HOME/MyFiles/Downloads"/chromebrew-packages-*.txt >/dev/null
  run env BACKUP_DIR="$BATS_TEST_TMPDIR/bk" "$CBS_BIN_DIR/chromebrew" -b
  [ "$status" -eq 0 ]
  ls "$BATS_TEST_TMPDIR/bk"/chromebrew-packages-*.txt >/dev/null
}

@test "--backup --dry-run writes nothing; without crew it fails" {
  run "$CBS_BIN_DIR/chromebrew" -b "$BATS_TEST_TMPDIR/pkgs.txt" -n
  [ "$status" -eq 0 ]
  assert_output_contains "would write 3 package name(s) to $BATS_TEST_TMPDIR/pkgs.txt"
  [ ! -e "$BATS_TEST_TMPDIR/pkgs.txt" ]
  without_crew
  run "$CBS_BIN_DIR/chromebrew" -b "$BATS_TEST_TMPDIR/pkgs.txt"
  [ "$status" -eq 1 ]
  assert_output_contains "nothing to back up"
}

@test "--restore installs the missing packages one by one and skips installed ones" {
  printf '# a backup\ngcc_lib\nhtop\n\nnano # editor\nbad name!\n' > "$BATS_TEST_TMPDIR/list.txt"
  run "$CBS_BIN_DIR/chromebrew" --restore "$BATS_TEST_TMPDIR/list.txt" -v
  [ "$status" -eq 0 ]
  assert_output_contains "ignoring a line that is not a package name: bad name!"
  assert_output_contains "3 package(s) listed, 1 already installed, 2 to install"
  assert_called "crew install htop"
  assert_called "crew install nano"
  assert_not_called "crew install gcc_lib"
  assert_output_contains "\$ yes | timeout -k 10 3600 crew install htop"
  assert_output_contains "2 installed, 1 already installed"
}

@test "--restore reports failures, honours --dry-run and needs crew and a readable file" {
  printf 'htop\nnano\n' > "$BATS_TEST_TMPDIR/list.txt"
  run env STUB_CREW_INSTALL_FAIL=nano "$CBS_BIN_DIR/chromebrew" --restore "$BATS_TEST_TMPDIR/list.txt"
  [ "$status" -eq 1 ]
  assert_output_contains "nano: crew install failed (exit code 1)"
  assert_output_contains "1 failed: nano (1 installed, 0 already installed)"
  : > "$STUB_LOG"
  run "$CBS_BIN_DIR/chromebrew" --restore "$BATS_TEST_TMPDIR/list.txt" -n
  [ "$status" -eq 0 ]
  assert_output_contains "would run: yes | timeout -k 10 3600 crew install htop"
  assert_not_called "crew install"
  run "$CBS_BIN_DIR/chromebrew" --restore "$BATS_TEST_TMPDIR/missing.txt"
  [ "$status" -eq 1 ]
  assert_output_contains "cannot read $BATS_TEST_TMPDIR/missing.txt"
  without_crew
  run "$CBS_BIN_DIR/chromebrew" --restore "$BATS_TEST_TMPDIR/list.txt"
  [ "$status" -eq 1 ]
  assert_output_contains "run 'chromebrew --install' first"
}

@test "a backup restores onto the same machine as a no-op" {
  run "$CBS_BIN_DIR/chromebrew" --backup "$BATS_TEST_TMPDIR/pkgs.txt"
  [ "$status" -eq 0 ]
  run "$CBS_BIN_DIR/chromebrew" --restore "$BATS_TEST_TMPDIR/pkgs.txt"
  [ "$status" -eq 0 ]
  assert_output_contains "every package in $BATS_TEST_TMPDIR/pkgs.txt is already installed"
  assert_not_called "crew install"
}
