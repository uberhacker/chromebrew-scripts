#!/usr/bin/env bash
# tests/install-smoke.sh - install.sh end to end, into a temporary prefix.
#
#   tests/install-smoke.sh
#
# CI runs this inside stock debian and alpine containers; it works on any
# machine with bash 4.4, coreutils, tar and curl. Nothing outside two
# temporary directories is touched: install.sh runs with CBS_SUDO empty (it
# never escalates), the commands run with --dry-run against a fake root
# (CBS_ROOT), and sudo, mount, reboot, make_dev_ssd.sh and crew are never
# called (a dry run only prints them, and the fake root has no crew).
#
# What it checks:
#   1. install.sh --prefix DIR installs the single file, the five command
#      symlinks and the bash completion; every command answers --help and
#      --version.
#   2. The commands detect the fake ChromeOS, plan their dry runs, write
#      their logs, and refuse what they must refuse.
#   3. --self-update --dry-run of the single file against a local fake
#      release: up to date, and refusing a release without a checksum.
#   4. install.sh --tree replaces the single file with the tree, install.sh
#      replaces the tree with the single file again, --uninstall removes
#      everything.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
prefix="$tmp/prefix"
fake="$tmp/root"
home="$tmp/home"
version=$(tr -d '[:space:]' < "$root/VERSION")
commands=(chromebrew powerwash rootfs rw cbs-check)

fail() { echo "install-smoke: FAIL: $*" >&2; exit 1; }

# install_sh ARGS...: install.sh without privilege escalation (the commands
# themselves keep their default "sudo", which a dry run only prints).
install_sh() { CBS_SUDO='' "$root/install.sh" "$@"; }

# expect PATTERN CMD...: CMD must succeed and print PATTERN.
expect() {
  local pat="$1" out rc=0; shift
  out=$("$@" 2>&1) || rc=$?
  [ "$rc" -eq 0 ] || { printf '%s\n' "$out"; fail "'$*' exited $rc"; }
  [[ "$out" == *"$pat"* ]] || { printf '%s\n' "$out"; fail "'$*' did not print: $pat"; }
}

# expect_fail PATTERN CMD...: CMD must fail and print PATTERN.
expect_fail() {
  local pat="$1" out rc=0; shift
  out=$("$@" 2>&1) || rc=$?
  [ "$rc" -ne 0 ] || { printf '%s\n' "$out"; fail "'$*' should have failed"; }
  [[ "$out" == *"$pat"* ]] || { printf '%s\n' "$out"; fail "'$*' did not print: $pat"; }
}

# ---- a fake ChromeOS root: verified boot on, / read-only, noexec mounts
mkdir -p "$fake/etc" "$fake/proc" "$fake/mnt/stateful_partition" "$fake/usr/local/bin" \
  "$fake/usr/share/vboot/bin" "$fake/home/chronos/user" "$home"
cat > "$fake/etc/lsb-release" <<'EOF'
CHROMEOS_RELEASE_NAME=Chrome OS
CHROMEOS_RELEASE_TRACK=stable-channel
CHROMEOS_RELEASE_VERSION=16093.68.0
CHROMEOS_RELEASE_CHROME_MILESTONE=130
CHROMEOS_RELEASE_DESCRIPTION=16093.68.0 (Official Build) stable-channel octopus
CHROMEOS_RELEASE_BOARD=octopus
EOF
printf 'cros_secure root=/dev/dm-0 rootwait ro dm="1 vroot none ro 1,0 1 verity"\n' > "$fake/proc/cmdline"
printf '/dev/root %s ext2 ro,relatime 0 0\n' "$fake" > "$fake/proc/mounts"
printf '/dev/sda1 %s/mnt/stateful_partition ext4 rw,nosuid,nodev,noexec,relatime 0 0\n' "$fake" >> "$fake/proc/mounts"
printf '/dev/sda1 %s/home/chronos/user ext4 rw,nosuid,nodev,noexec,relatime 0 0\n' "$fake" >> "$fake/proc/mounts"

export CBS_HOME="$home" CBS_ROOT="$fake" NO_COLOR=1
export CBS_CROSSYSTEM=no-crossystem CBS_SYSTEM_CONFIG="$fake/etc/chromebrew-scripts.conf"
export LOG_DIR="$tmp/logs"
unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME

# ---- 1. the single file and its symlinks
echo "== install.sh --prefix $prefix"
expect "(single file) to $prefix/bin/chromebrew-scripts" install_sh --prefix "$prefix"
grep -q '^CBS_BUNDLED=1$' "$prefix/bin/chromebrew-scripts" || fail "$prefix/bin/chromebrew-scripts is not a single-file build"
for c in "${commands[@]}"; do
  [ -L "$prefix/bin/$c" ] || fail "$prefix/bin/$c is not a symlink"
  [ "$(readlink "$prefix/bin/$c")" = chromebrew-scripts ] || fail "$prefix/bin/$c points at $(readlink "$prefix/bin/$c")"
done
[ -f "$prefix/share/bash-completion/completions/chromebrew-scripts" ] || fail "no bash completion installed"
for c in chromebrew-scripts "${commands[@]}"; do
  expect "Usage:" "$prefix/bin/$c" --help
  expect "chromebrew-scripts $version (" "$prefix/bin/$c" --version
  expect "single file" "$prefix/bin/$c" --version
done
expect "complete -F _chromebrew_scripts" "$prefix/bin/chromebrew-scripts" --completion bash

# ---- 2. dry runs against the fake root
echo "== dry runs"
expect "would run: sudo mount -o remount,rw $fake" "$prefix/bin/rw" --dry-run --yes
expect "0 ok, 0 updated, 0 skipped, 0 failed, 3 dry-run" "$prefix/bin/rw" --dry-run --yes
expect "already mounted ro" "$prefix/bin/rw" --undo -ny
expect "would run: echo clobber | sudo tee $fake/mnt/stateful_partition/.update_available" "$prefix/bin/powerwash" -ny
expect "would run: sudo reboot" "$prefix/bin/chromebrew-scripts" powerwash -ny
expect "would run: sudo $fake/usr/share/vboot/bin/make_dev_ssd.sh --remove_rootfs_verification --partitions 2" \
  "$prefix/bin/rootfs" -ny -- --partitions 2
expect "not installed" "$prefix/bin/chromebrew" --status
expect "would clear $fake/usr/local/*" "$prefix/bin/chromebrew" --remove -ny
expect_fail "chromebrew is not installed" "$prefix/bin/chromebrew" --update -ny
if [ "$(id -u)" -eq 0 ]; then
  expect_fail "must not be installed as root" "$prefix/bin/chromebrew" --install -ny
else
  expect "would download https://raw.githubusercontent.com/chromebrew/chromebrew/master/install.sh" \
    env MIN_FREE_MB=1 "$prefix/bin/chromebrew" --install -ny
fi
expect "stable (supported by the Chromebrew installer)" "$prefix/bin/cbs-check" --offline
expect "on (dm-verity in $fake/proc/cmdline)" "$prefix/bin/cbs-check" --offline
expect "not checked (--offline)" "$prefix/bin/chromebrew-scripts" check --offline
expect_fail "unknown option: --fix" "$prefix/bin/cbs-check" --fix
# nothing without a terminal and without --yes
expect_fail "refusing to continue: stdin is not a terminal" "$prefix/bin/rw" --dry-run </dev/null
# off ChromeOS the commands refuse
expect_fail "not ChromeOS" env CBS_ROOT="$tmp/not-chromeos" "$prefix/bin/rw" -ny
# every run left a log
ls "$LOG_DIR"/*-rw-*.log "$LOG_DIR"/*-powerwash-*.log "$LOG_DIR"/*-cbs-check-*.log >/dev/null || fail "no logs in $LOG_DIR"
grep -q '^# command  rw --dry-run --yes$' "$LOG_DIR"/*-rw-*.log || fail "the rw log has no command line"
[ -L "$LOG_DIR/latest.log" ] || fail "no latest.log"
[ ! -e "$fake/mnt/stateful_partition/.update_available" ] || fail "the dry run wrote the powerwash marker"

# ---- 3. --self-update --dry-run against a local fake release
echo "== self-update dry run"
rel="$tmp/rel/releases/latest/download"
mkdir -p "$rel"
cp "$prefix/bin/chromebrew-scripts" "$rel/chromebrew-scripts"
(cd "$rel" && sha256sum chromebrew-scripts > chromebrew-scripts.sha256)
export CHROMEBREW_SCRIPTS_ALLOW_FILE_SOURCE=1 SELF_UPDATE_REPO="file://$tmp/rel"
expect "already up to date: chromebrew-scripts $version" "$prefix/bin/chromebrew-scripts" --self-update --dry-run
expect "current (matches the latest release)" "$prefix/bin/cbs-check"
rm "$rel/chromebrew-scripts.sha256"
expect_fail "refusing an unverified update" "$prefix/bin/rw" --self-update --dry-run
expect_fail "refusing an unverified update" "$prefix/bin/chromebrew-scripts" --self-update
cmp -s "$prefix/bin/chromebrew-scripts" "$rel/chromebrew-scripts" || fail "the single file was changed"
unset CHROMEBREW_SCRIPTS_ALLOW_FILE_SOURCE SELF_UPDATE_REPO

# ---- 4. the tree layout, back to the single file, uninstall
echo "== install.sh --tree, then the single file again, then --uninstall"
expect "(tree) to $prefix/share/chromebrew-scripts" install_sh --prefix "$prefix" --tree
[ -f "$prefix/share/chromebrew-scripts/bin/chromebrew-scripts" ] || fail "no tree installed"
[ -d "$prefix/share/chromebrew-scripts/lib/core" ] || fail "the tree has no lib/core"
[ "$(readlink "$prefix/bin/rw")" = "$prefix/share/chromebrew-scripts/bin/chromebrew-scripts" ] || fail "rw does not point into the tree"
expect "chromebrew-scripts $version" "$prefix/bin/rw" --version
case "$("$prefix/bin/rw" --version)" in *"single file"*) fail "rw still runs the single file after --tree" ;; esac
expect "would run: sudo mount -o remount,rw $fake" "$prefix/bin/rw" -ny
expect "removed the previous tree installation" install_sh --prefix "$prefix"
[ ! -e "$prefix/share/chromebrew-scripts" ] || fail "the tree was left behind"
expect "single file" "$prefix/bin/rw" --version
install_sh --prefix "$prefix" --uninstall
for c in chromebrew-scripts "${commands[@]}"; do
  if [ -e "$prefix/bin/$c" ] || [ -L "$prefix/bin/$c" ]; then fail "$prefix/bin/$c was left behind"; fi
done
[ ! -e "$prefix/share/bash-completion/completions/chromebrew-scripts" ] || fail "the completion was left behind"
expect "nothing of chromebrew-scripts found" install_sh --prefix "$prefix" --uninstall

echo "install-smoke: ok"
