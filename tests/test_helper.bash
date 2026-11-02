#!/usr/bin/env bash
# tests/test_helper.bash - shared bats setup.
# shellcheck disable=SC2034  # variables here are used by the .bats files

# `run --separate-stderr` and `run -N` need bats-core 1.5 or newer.
bats_require_minimum_version 1.5.0

REPO_ROOT=$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)
STUBS="$REPO_ROOT/tests/stubs"
# CBS_TEST_TARGET=bundle runs the entry-point tests through a single-file
# build instead of bin/ (tests/run.sh runs both).
CBS_TEST_TARGET="${CBS_TEST_TARGET:-modular}"
export REPO_ROOT STUBS CBS_TEST_TARGET

# setup_sandbox: a fake filesystem under $SANDBOX, stubs on PATH, a call log,
# and $CBS_BIN_DIR holding the commands under test (bin/ or a fresh bundle
# with its command symlinks).
setup_sandbox() {
  SANDBOX="$BATS_TEST_TMPDIR/root"
  export SANDBOX
  mkdir -p "$SANDBOX/etc" "$SANDBOX/mnt/stateful_partition" "$SANDBOX/usr/local" \
    "$SANDBOX/usr/share/vboot/bin" "$SANDBOX/home/chronos/user" "$SANDBOX/proc"
  export CBS_ROOT="$SANDBOX"
  export CBS_HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$CBS_HOME"
  export CBS_ASSUME_CHROMEOS=1
  export NO_COLOR=1
  export STUB_LOG="$BATS_TEST_TMPDIR/calls.log"
  : > "$STUB_LOG"
  PATH_NO_STUBS="$PATH"
  export PATH="$STUBS:$PATH"
  cp -L "$STUBS/stub.sh" "$SANDBOX/usr/share/vboot/bin/make_dev_ssd.sh"
  # Nothing from the caller's environment may leak into the settings.
  unset CBS_YES CBS_DRY_RUN CBS_LSB_RELEASE CBS_STATEFUL CBS_VBOOT_BIN CBS_USER_HOME \
    CBS_ROOTFS_MOUNT CBS_PROC_MOUNTS CBS_PROC_CMDLINE CBS_CROSTINI_DIR CBS_CROSSYSTEM \
    CBS_CONFIG_FILE CBS_LOG_PATH CBS_SUDO \
    SELF_UPDATE_REPO SELF_UPDATE_BRANCH TIMEOUT CREW_TIMEOUT DOWNLOAD_TIMEOUT \
    CREW_INSTALLER_URL CREW_PREFIX FORCE_INSTALL MIN_FREE_MB BACKUP_DIR COLOR \
    LOGGING LOG_DIR LOG_KEEP \
    CBS_CREW_INSTALLER_URL CBS_CREW_TIMEOUT CBS_CURL_TIMEOUT CBS_PREFIX CREW_FORCE_INSTALL \
    CBS_REPO CBS_REF CBS_TARBALL_URL XDG_CONFIG_HOME XDG_STATE_HOME XDG_DATA_HOME \
    CHROMEBREW_SCRIPTS_ALLOW_FILE_SOURCE 2>/dev/null || true
  export CBS_SYSTEM_CONFIG="$SANDBOX/etc/chromebrew-scripts.conf"
  # crossystem is a stub only where a test puts it on PATH.
  export CBS_CROSSYSTEM="$BATS_TEST_TMPDIR/no-crossystem"
  # Where the run logs land by default (root and user differ).
  if [ "$(id -u)" -eq 0 ]; then
    LOG_DIR_DEFAULT="$SANDBOX/var/log/chromebrew-scripts"
  else
    LOG_DIR_DEFAULT="$CBS_HOME/.local/state/chromebrew-scripts"
  fi
  export LOG_DIR_DEFAULT
  if [ "$CBS_TEST_TARGET" = bundle ]; then
    CBS_BIN_DIR="$BATS_TEST_TMPDIR/bin"
    build_bundle "$CBS_BIN_DIR"
  else
    CBS_BIN_DIR="$REPO_ROOT/bin"
  fi
  export CBS_BIN_DIR
}

# build_bundle DIR: a single-file build at DIR/chromebrew-scripts with the
# command symlinks next to it.
build_bundle() {
  local dir="$1" cmd
  mkdir -p "$dir"
  "$REPO_ROOT/build.sh" "$dir/chromebrew-scripts" >/dev/null
  for cmd in chromebrew powerwash rootfs rw cbs-check; do
    ln -sfn chromebrew-scripts "$dir/$cmd"
  done
}

# without_crew: take the crew stub off PATH (Chromebrew "not installed").
without_crew() {
  local d="$BATS_TEST_TMPDIR/stubs-nocrew" f
  mkdir -p "$d"
  for f in "$STUBS"/*; do
    [ "${f##*/}" = crew ] && continue
    ln -sfn "$f" "$d/${f##*/}"
  done
  export PATH="$d:$PATH_NO_STUBS"
}

# run_as_user CMD...: `run` CMD as an unprivileged user (Chromebrew refuses
# to install as root). When the tests themselves run as root (containers),
# drop to uid 65534 with setpriv after making the test's temp tree
# world-writable; EXPECT_UID is the uid the command ran as.
run_as_user() {
  if [ "$(id -u)" -eq 0 ]; then
    command -v setpriv >/dev/null 2>&1 || skip "setpriv not available"
    chmod -R a+rwX "$BATS_TEST_TMPDIR" "$BATS_RUN_TMPDIR" 2>/dev/null || true
    setpriv --reuid=65534 --regid=65534 --clear-groups true 2>/dev/null || skip "cannot drop privileges"
    EXPECT_UID=65534
    run setpriv --reuid=65534 --regid=65534 --clear-groups \
      env HOME="$CBS_HOME" TMPDIR="$BATS_TEST_TMPDIR" "$@"
  else
    EXPECT_UID=$(id -u)
    run "$@"
  fi
}

# write_lsb_release [NAME] [TRACK] [VERSION]: make the sandbox look like ChromeOS.
write_lsb_release() {
  local name="${1:-Chrome OS}" track="${2:-stable-channel}" version="${3:-16093.68.0}"
  {
    printf 'CHROMEOS_RELEASE_NAME=%s\n' "$name"
    printf 'CHROMEOS_RELEASE_TRACK=%s\n' "$track"
    printf 'CHROMEOS_RELEASE_VERSION=%s\n' "$version"
    printf 'CHROMEOS_RELEASE_DESCRIPTION=%s (Official Build) %s octopus\n' "$version" "$track"
    printf 'CHROMEOS_RELEASE_CHROME_MILESTONE=130\n'
    printf 'CHROMEOS_RELEASE_BOARD=octopus\n'
    printf 'CHROMEOS_RELEASE_BUILD_TYPE=Official Build\n'
  } > "$SANDBOX/etc/lsb-release"
}

# tgit DIR ARGS...: git in DIR with a fixed identity (for fixtures).
tgit() {
  git -C "$1" -c user.name=test -c user.email=test@example.com -c advice.detachedHead=false "${@:2}"
}

# make_upstream DIR: a git repository on branch main holding a copy of this
# toolkit's sources, to clone "installations" from.
make_upstream() {
  local dir="$1"
  mkdir -p "$dir"
  cp -R "$REPO_ROOT"/{bin,lib,completions} "$REPO_ROOT"/{VERSION,build.sh,config.example} "$dir/"
  git init -q "$dir"
  git -C "$dir" symbolic-ref HEAD refs/heads/main
  tgit "$dir" add -A
  tgit "$dir" commit -q -m "initial"
}

# bump_upstream DIR VERSION: commit a new VERSION in the fixture repository.
bump_upstream() {
  printf '%s\n' "$2" > "$1/VERSION"
  tgit "$1" add -A
  tgit "$1" commit -q -m "version $2"
}

# make_release DIR BUNDLE VERSION: a fake GitHub "latest release" under DIR
# (releases/latest/download/chromebrew-scripts and its .sha256), made from
# BUNDLE with its version changed to VERSION. Reached with
# SELF_UPDATE_REPO=file://DIR and CHROMEBREW_SCRIPTS_ALLOW_FILE_SOURCE=1.
make_release() {
  local d="$1/releases/latest/download"
  mkdir -p "$d"
  sed "s/^CBS_BUNDLE_VERSION='.*'\$/CBS_BUNDLE_VERSION='$3'/" "$2" > "$d/chromebrew-scripts"
  (cd "$d" && sha256sum chromebrew-scripts > chromebrew-scripts.sha256)
}

# write_mounts ROOT_OPTS STATEFUL_OPTS HOME_OPTS: a /proc/mounts for the sandbox.
write_mounts() {
  printf '/dev/root %s ext2 %s 0 0\n/dev/sda1 %s/mnt/stateful_partition ext4 %s 0 0\n/dev/sda1 %s/home/chronos/user ext4 %s 0 0\n' \
    "$SANDBOX" "${1:-ro,relatime}" "$SANDBOX" "${2:-rw,nosuid,nodev,noexec,relatime}" "$SANDBOX" "${3:-rw,nosuid,nodev,noexec}" \
    > "$SANDBOX/proc/mounts"
}

# write_cmdline verified|plain: a /proc/cmdline with or without dm-verity.
write_cmdline() {
  if [ "${1:-verified}" = verified ]; then
    printf 'cros_secure console= init=/sbin/init root=/dev/dm-0 rootwait ro dm_verity.error_behavior=3 dm="1 vroot none ro 1,0 3000 verity payload=PARTUUID=%%U/PARTNROFF=1 alg=sha256 root_hexdigest=abc salt=def" noinitrd\n'
  else
    printf 'cros_secure console= init=/sbin/init root=PARTUUID=%%U/PARTNROFF=1 rootwait rw dm_verity.error_behavior=3 noinitrd\n'
  fi > "$SANDBOX/proc/cmdline"
}

# use_crossystem_stub: put a crossystem on PATH that answers from
# STUB_CROSSYSTEM_<flag> (default 1).
use_crossystem_stub() {
  export CBS_CROSSYSTEM="$STUBS/crossystem"
}

# run_fn FUNC ARGS...: bats' `run` for a toolkit function after load_cbs,
# which defines the toolkit's own `run`. Runs FUNC in a subshell and sets
# $status and $output (stdout and stderr together).
run_fn() {
  status=0
  output=$("$@" 2>&1) || status=$?
}

calls() { cat "$STUB_LOG"; }

assert_called() {
  grep -qF -- "$1" "$STUB_LOG" || {
    echo "expected a call matching: $1"
    echo "calls were:"
    cat "$STUB_LOG"
    return 1
  }
}

assert_not_called() {
  if grep -qF -- "$1" "$STUB_LOG"; then
    echo "did not expect a call matching: $1"
    echo "calls were:"
    cat "$STUB_LOG"
    return 1
  fi
}

assert_output_contains() {
  # shellcheck disable=SC2154  # $output is set by bats' run
  [[ "$output" == *"$1"* ]] || {
    echo "expected output to contain: $1"
    echo "output was:"
    echo "$output"
    return 1
  }
}

assert_output_not_contains() {
  [[ "$output" != *"$1"* ]] || {
    echo "did not expect output to contain: $1"
    echo "output was:"
    echo "$output"
    return 1
  }
}

# assert_contains HAYSTACK NEEDLE
assert_contains() {
  if [[ "$1" != *"$2"* ]]; then
    echo "expected to find: $2"
    echo "in: $1"
    return 1
  fi
}

# assert_not_contains HAYSTACK NEEDLE
assert_not_contains() {
  if [[ "$1" == *"$2"* ]]; then
    echo "did not expect to find: $2"
    echo "in: $1"
    return 1
  fi
}

# assert_equal EXPECTED ACTUAL
assert_equal() {
  if [ "$1" != "$2" ]; then
    echo "expected: $1"
    echo "actual:   $2"
    return 1
  fi
}

# assert_version_output: $output is "chromebrew-scripts <VERSION>..." for the
# target under test (the bundle adds "(git ..., single file)").
assert_version_output() {
  local v
  v=$(tr -d '[:space:]' < "$REPO_ROOT/VERSION")
  [[ "$output" == "chromebrew-scripts $v"* ]] || {
    echo "expected a version line for $v, got: $output"
    return 1
  }
  if [ "$CBS_TEST_TARGET" = bundle ]; then
    assert_output_contains "single file"
  fi
}

# log_files: the run logs written under the default directory, oldest first.
log_files() {
  local f
  for f in "$LOG_DIR_DEFAULT"/[0-9]*-*.log; do
    [ -f "$f" ] && printf '%s\n' "$f"
  done
  return 0
}

# load_cbs: source every module into the test shell without running main,
# for unit tests of single functions. bats owns the EXIT trap.
load_cbs() {
  export CBS_SKIP_EXIT_TRAP=1
  export CBS_OUT=1
  export CBS_COLOR="${CBS_COLOR:-never}"
  CBS_BUNDLED=0
  CBS_BIN="$REPO_ROOT/bin/chromebrew-scripts"
  CBS_ROOT_DIR="$REPO_ROOT"
  CBS_COMMANDS=(chromebrew powerwash rootfs rw check)
  set +u
  local f
  for f in log util config args chromeos crew runner runlog selfupdate; do
    # shellcheck disable=SC1090
    source "$REPO_ROOT/lib/core/$f.sh"
  done
  for f in "$REPO_ROOT"/lib/cmd/*.sh; do
    # shellcheck disable=SC1090
    source "$f"
  done
  # version_string lives in the entry point; a small stand-in for the tests.
  # shellcheck disable=SC2317  # called by the modules under test
  version_string() { printf 'chromebrew-scripts %s (test)\n' "$(tr -d '[:space:]' < "$REPO_ROOT/VERSION")"; }
  user_init
  config_load
  args_apply
  chromeos_detect
}

# Remove temp files created through tmp_dir/tmp_file during a test.
teardown() {
  declare -F tmp_cleanup >/dev/null && tmp_cleanup
  return 0
}
