#!/usr/bin/env bats
# tests/unit/selfupdate.bats - --self-update in its three modes: a git
# checkout, a tree installation and a single file. Sources are local
# fixtures reached through file:// (CHROMEBREW_SCRIPTS_ALLOW_FILE_SOURCE=1).

load ../test_helper

setup() {
  setup_sandbox
  export CHROMEBREW_SCRIPTS_ALLOW_FILE_SOURCE=1
}

version() { tr -d '[:space:]' < "$REPO_ROOT/VERSION"; }

# tree_mode_only: the git and tree modes do not depend on the target under
# test; run them once, with the modular build.
tree_mode_only() {
  [ "$CBS_TEST_TARGET" = modular ] || skip "git and tree installations are tested with the modular build"
  command -v git >/dev/null 2>&1 || skip "git not available"
}

@test "--self-update rejects extra arguments and a source that is not https" {
  run "$CBS_BIN_DIR/rw" --self-update extra
  [ "$status" -eq 2 ]
  assert_output_contains "unexpected argument: extra"
  run "$CBS_BIN_DIR/rw" --self-update --dry-run --source http://example.test/repo
  [ "$status" -eq 2 ]
  assert_output_contains "invalid value for SELF_UPDATE_REPO (flag) ignored"
  [ -z "$(calls)" ]
}

@test "a git checkout fast-forwards from its origin and logs the run" {
  tree_mode_only
  local up="$BATS_TEST_TMPDIR/upstream" inst="$BATS_TEST_TMPDIR/inst"
  make_upstream "$up"
  git clone -q "file://$up" "$inst"
  bump_upstream "$up" 9.9.9
  run "$inst/bin/rw" --self-update --dry-run -v
  [ "$status" -eq 0 ]
  assert_output_contains "no SELF_UPDATE_REPO configured; following the checkout's origin"
  assert_output_contains "source: file://$up (branch main)"
  assert_output_contains "installed: $(version) ("
  assert_output_contains "would fast-forward"
  assert_output_contains "(1 new commit(s) on main)"
  [ "$(cat "$inst/VERSION")" = "$(version)" ]
  run "$inst/bin/rw" --self-update
  [ "$status" -eq 0 ]
  assert_output_contains "updated $(version) ("
  assert_output_contains "-> 9.9.9 ("
  [ "$(cat "$inst/VERSION")" = 9.9.9 ]
  run "$inst/bin/rw" --version
  [[ "$output" == "chromebrew-scripts 9.9.9 (git "* ]]
  run "$inst/bin/rw" --self-update
  [ "$status" -eq 0 ]
  assert_output_contains "already up to date: 9.9.9"
  ls "$LOG_DIR_DEFAULT"/*-self-update-*.log >/dev/null
  grep -q '^# command  self-update --self-update$' "$LOG_DIR_DEFAULT/latest.log"
}

@test "a git checkout with local changes or another origin is refused; --source re-points it" {
  tree_mode_only
  local up="$BATS_TEST_TMPDIR/upstream" up2="$BATS_TEST_TMPDIR/upstream2" inst="$BATS_TEST_TMPDIR/inst"
  make_upstream "$up"
  git clone -q "file://$up" "$inst"
  echo dirty >> "$inst/VERSION"
  run "$inst/bin/rw" --self-update
  [ "$status" -eq 1 ]
  assert_output_contains "refusing to update: $inst has local changes"
  git -C "$inst" checkout -q -- VERSION
  run env SELF_UPDATE_REPO=https://github.com/someone/else "$inst/bin/rw" --self-update --dry-run
  [ "$status" -eq 1 ]
  assert_output_contains "checkout origin (file://$up) does not match the configured source (https://github.com/someone/else)"
  [ "$(git -C "$inst" remote get-url origin)" = "file://$up" ]
  git clone -q "file://$up" "$up2"
  bump_upstream "$up2" 8.8.8
  run "$inst/bin/rw" --self-update --source "file://$up2"
  [ "$status" -eq 0 ]
  assert_output_contains "re-pointing origin from file://$up to file://$up2 (--source)"
  assert_output_contains "-> 8.8.8 ("
  [ "$(git -C "$inst" remote get-url origin)" = "file://$up2" ]
  [ "$(cat "$inst/VERSION")" = 8.8.8 ]
}

@test "a git checkout follows --branch / SELF_UPDATE_BRANCH" {
  tree_mode_only
  local up="$BATS_TEST_TMPDIR/upstream" inst="$BATS_TEST_TMPDIR/inst"
  make_upstream "$up"
  git clone -q "file://$up" "$inst"
  tgit "$up" checkout -q -b feature
  bump_upstream "$up" 7.7.7
  tgit "$up" checkout -q main
  # another branch is a switch, not a fast-forward, and the dry run says so
  run "$inst/bin/rw" --self-update --branch feature -n
  [ "$status" -eq 0 ]
  assert_output_contains "would switch from main to feature at "
  [ "$(cat "$inst/VERSION")" = "$(version)" ]
  run "$inst/bin/rw" --self-update --branch feature
  [ "$status" -eq 0 ]
  assert_output_contains "source: file://$up (branch feature)"
  assert_output_contains "switching from main to feature"
  assert_output_contains "switched to feature: 7.7.7 ("
  [ "$(cat "$inst/VERSION")" = 7.7.7 ]
  [ "$(git -C "$inst" symbolic-ref --short HEAD)" = feature ]
  run env SELF_UPDATE_BRANCH=main "$inst/bin/rw" --self-update
  [ "$status" -eq 0 ]
  [ "$(cat "$inst/VERSION")" = "$(version)" ]
  [ "$(git -C "$inst" symbolic-ref --short HEAD)" = main ]
}

# make_tree DIR: a tree installation (no .git) of this toolkit at DIR.
make_tree() {
  mkdir -p "$1"
  cp -R "$REPO_ROOT"/{bin,lib,completions} "$REPO_ROOT"/{VERSION,build.sh,config.example} "$1/"
}

# make_tarball_release REPO BRANCH VERSION [BREAK]: REPO/archive/refs/heads/BRANCH.tar.gz
# holding a copy of the toolkit at VERSION (BREAK=nolib leaves lib/core out).
make_tarball_release() {
  local repo="$1" branch="$2" src="$BATS_TEST_TMPDIR/src-$2/chromebrew-scripts-$2"
  mkdir -p "$src" "$repo/archive/refs/heads"
  make_tree "$src"
  printf '%s\n' "$3" > "$src/VERSION"
  [ "${4:-}" = nolib ] && rm -rf "$src/lib/core"
  tar -czf "$repo/archive/refs/heads/$branch.tar.gz" -C "$(dirname "$src")" "$(basename "$src")"
}

@test "a tree installation swaps in the downloaded branch tarball" {
  tree_mode_only
  local tree="$BATS_TEST_TMPDIR/tree" repo="$SANDBOX/fake-repo"
  make_tree "$tree"
  make_tarball_release "$repo" main 9.9.9
  export SELF_UPDATE_REPO="file://$repo" SELF_UPDATE_BRANCH=main
  run "$tree/bin/rw" --self-update --dry-run
  [ "$status" -eq 0 ]
  assert_output_contains "source: file://$repo/archive/refs/heads/main.tar.gz"
  assert_output_contains "installed: $(version) (not a git checkout)"
  assert_output_contains "would replace $tree ($(version)) with 9.9.9 from main"
  [ "$(cat "$tree/VERSION")" = "$(version)" ]
  run "$tree/bin/rw" --self-update
  [ "$status" -eq 0 ]
  assert_output_contains "updated $(version) -> 9.9.9 (main)"
  [ "$(cat "$tree/VERSION")" = 9.9.9 ]
  [ -f "$tree/lib/core/log.sh" ]
  run "$tree/bin/rw" --version
  [[ "$output" == "chromebrew-scripts 9.9.9" ]]
  [ -z "$(find "$BATS_TEST_TMPDIR" -maxdepth 1 -name '.tree.*')" ]
}

@test "a tree installation is left alone when the download is not a toolkit" {
  tree_mode_only
  local tree="$BATS_TEST_TMPDIR/tree" repo="$SANDBOX/fake-repo"
  make_tree "$tree"
  make_tarball_release "$repo" main 9.9.9 nolib
  export SELF_UPDATE_REPO="file://$repo" SELF_UPDATE_BRANCH=main
  run "$tree/bin/rw" --self-update
  [ "$status" -eq 1 ]
  assert_output_contains "downloaded tree has no lib/core"
  [ "$(cat "$tree/VERSION")" = "$(version)" ]
  run env SELF_UPDATE_BRANCH=missing "$tree/bin/rw" --self-update
  [ "$status" -eq 1 ]
  assert_output_contains "download failed: file://$repo/archive/refs/heads/missing.tar.gz"
  [ "$(cat "$tree/VERSION")" = "$(version)" ]
}

@test "a single file installs the latest release after verifying its checksum" {
  local dir="$BATS_TEST_TMPDIR/sfu" rel="$SANDBOX/rel"
  build_bundle "$dir"
  make_release "$rel" "$dir/chromebrew-scripts" 9.9.9
  export SELF_UPDATE_REPO="file://$rel"
  run "$dir/rw" --self-update --dry-run
  [ "$status" -eq 0 ]
  assert_output_contains "source: file://$rel/releases/latest/download/chromebrew-scripts"
  assert_output_contains "installed: chromebrew-scripts $(version) (git "
  assert_output_contains "would replace $dir/chromebrew-scripts: $(version) (git "
  assert_output_contains "-> 9.9.9 (git "
  grep -q "^CBS_BUNDLE_VERSION='$(version)'$" "$dir/chromebrew-scripts"
  run "$dir/rw" --self-update -v
  [ "$status" -eq 0 ]
  assert_output_contains "checksum ok: "
  assert_output_contains "updated $(version) (git "
  assert_output_contains "-> 9.9.9 (git "
  grep -q "^CBS_BUNDLE_VERSION='9.9.9'$" "$dir/chromebrew-scripts"
  [ "$(stat -c %a "$dir/chromebrew-scripts")" = 755 ]
  [ "$(readlink "$dir/rw")" = chromebrew-scripts ]
  run "$dir/rw" --version
  [[ "$output" == "chromebrew-scripts 9.9.9 (git "*", single file)" ]]
  : > "$STUB_LOG"
  run "$dir/rw" --self-update
  [ "$status" -eq 0 ]
  assert_output_contains "already up to date: chromebrew-scripts 9.9.9"
  # only the checksum was fetched the second time
  [ "$(grep -c '^curl ' "$STUB_LOG")" -eq 1 ]
  assert_called "chromebrew-scripts.sha256"
  [ -z "$(find "$dir" -name '.chromebrew-scripts.new.*')" ]
}

@test "a single file refuses an unverified, corrupt or foreign download" {
  local dir="$BATS_TEST_TMPDIR/sfu" rel="$SANDBOX/rel" d
  build_bundle "$dir"
  d="$rel/releases/latest/download"
  cp "$dir/chromebrew-scripts" "$BATS_TEST_TMPDIR/orig"
  export SELF_UPDATE_REPO="file://$rel"
  # nothing published at all
  run "$dir/rw" --self-update
  [ "$status" -eq 1 ]
  assert_output_contains "no chromebrew-scripts.sha256 is published with the latest release; refusing an unverified update"
  # an asset without a checksum
  make_release "$rel" "$dir/chromebrew-scripts" 9.9.9
  rm "$d/chromebrew-scripts.sha256"
  run "$dir/rw" --self-update
  [ "$status" -eq 1 ]
  assert_output_contains "refusing an unverified update"
  # a checksum that does not match
  echo "0000000000000000000000000000000000000000000000000000000000000000  chromebrew-scripts" > "$d/chromebrew-scripts.sha256"
  run "$dir/rw" --self-update
  [ "$status" -eq 1 ]
  assert_output_contains "checksum mismatch for chromebrew-scripts"
  # not a checksum at all
  echo "not a checksum" > "$d/chromebrew-scripts.sha256"
  run "$dir/rw" --self-update
  [ "$status" -eq 1 ]
  assert_output_contains "does not contain a sha256"
  # a file that is not a single-file build
  make_release "$rel" "$dir/chromebrew-scripts" 9.9.9
  sed -i 's/^CBS_BUNDLED=1$/CBS_BUNDLED=0/' "$d/chromebrew-scripts"
  (cd "$d" && sha256sum chromebrew-scripts > chromebrew-scripts.sha256)
  run "$dir/rw" --self-update
  [ "$status" -eq 1 ]
  assert_output_contains "is not a single-file build of chromebrew-scripts; $dir/chromebrew-scripts left untouched"
  # a file that does not parse
  make_release "$rel" "$dir/chromebrew-scripts" 9.9.9
  echo 'if then fi (' >> "$d/chromebrew-scripts"
  (cd "$d" && sha256sum chromebrew-scripts > chromebrew-scripts.sha256)
  run "$dir/rw" --self-update
  [ "$status" -eq 1 ]
  assert_output_contains "does not parse; $dir/chromebrew-scripts left untouched"
  cmp -s "$dir/chromebrew-scripts" "$BATS_TEST_TMPDIR/orig"
  [ -z "$(find "$dir" -name '.chromebrew-scripts.new.*')" ]
  # a branch setting is meaningless for releases
  make_release "$rel" "$dir/chromebrew-scripts" 9.9.9
  run "$dir/rw" --self-update --dry-run --branch dev
  [ "$status" -eq 0 ]
  assert_output_contains "ignored for a single-file build"
}
