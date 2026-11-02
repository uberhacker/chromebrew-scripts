#!/usr/bin/env bats
# tests/unit/bundle.bats - build.sh and the single-file build.

load ../test_helper

setup() { setup_sandbox; }

version() { tr -d '[:space:]' < "$REPO_ROOT/VERSION"; }

@test "build.sh makes a single file that parses, with every module and the completion embedded" {
  local dir="$BATS_TEST_TMPDIR/b" m n
  mkdir -p "$dir"
  run "$REPO_ROOT/build.sh" "$dir/chromebrew-scripts"
  [ "$status" -eq 0 ]
  n=$(ls "$REPO_ROOT"/lib/core/*.sh "$REPO_ROOT"/lib/cmd/*.sh | wc -l)
  assert_output_contains "built $dir/chromebrew-scripts ($(version), git "
  assert_output_contains ", $n modules, "
  bash -n "$dir/chromebrew-scripts"
  [ -x "$dir/chromebrew-scripts" ]
  [ "$(grep -c '^CBS_BUNDLED=1$' "$dir/chromebrew-scripts")" -eq 1 ]
  ! grep -q '^CBS_BUNDLED=0' "$dir/chromebrew-scripts"
  ! grep -q 'source "\$CBS_ROOT_DIR' "$dir/chromebrew-scripts"
  grep -q "^CBS_BUNDLE_VERSION='$(version)'$" "$dir/chromebrew-scripts"
  grep -q "^CBS_BUNDLE_COMMIT='" "$dir/chromebrew-scripts"
  grep -q '^cbs_completion_script()' "$dir/chromebrew-scripts"
  for m in "$REPO_ROOT"/lib/core/*.sh "$REPO_ROOT"/lib/cmd/*.sh; do
    grep -q "^# ==== lib/${m#"$REPO_ROOT"/lib/} ====$" "$dir/chromebrew-scripts"
  done
  [ "$(grep -c '^#!/usr/bin/env bash$' "$dir/chromebrew-scripts")" -eq 1 ]
  # -o and the default output
  run "$REPO_ROOT/build.sh" -o "$dir/other"
  [ "$status" -eq 0 ]
  [ -x "$dir/other" ]
  run "$REPO_ROOT/build.sh" --bogus
  [ "$status" -eq 2 ]
}

@test "the single file runs on its own and dispatches on its name or its first argument" {
  local dir="$BATS_TEST_TMPDIR/alone"
  mkdir -p "$dir"
  "$REPO_ROOT/build.sh" "$dir/chromebrew-scripts" >/dev/null
  ln -s chromebrew-scripts "$dir/rw"
  run "$dir/chromebrew-scripts" --version
  [ "$status" -eq 0 ]
  [[ "$output" == "chromebrew-scripts $(version) (git "*", single file)" ]]
  run "$dir/rw" --help
  [ "$status" -eq 0 ]
  assert_output_contains "Usage: rw [options]"
  run "$dir/chromebrew-scripts" rw --help
  [ "$status" -eq 0 ]
  assert_output_contains "Usage: rw [options]"
  run "$dir/chromebrew-scripts" check --help
  [ "$status" -eq 0 ]
  assert_output_contains "Usage: cbs-check [options]"
  run "$dir/chromebrew-scripts" rw -ny
  [ "$status" -eq 0 ]
  assert_output_contains "would run: sudo mount -o remount,rw $SANDBOX"
  run "$dir/rw" -y
  [ "$status" -eq 0 ]
  assert_called "mount -o remount,rw $SANDBOX"
  # copied somewhere else under another name it still works: nothing is
  # loaded from lib/
  mkdir "$BATS_TEST_TMPDIR/elsewhere"
  cp "$dir/chromebrew-scripts" "$BATS_TEST_TMPDIR/elsewhere/cbs"
  run "$BATS_TEST_TMPDIR/elsewhere/cbs" powerwash -ny
  [ "$status" -eq 0 ]
  assert_output_contains "would run: sudo reboot"
  run "$BATS_TEST_TMPDIR/elsewhere/cbs" --version
  [ "$status" -eq 0 ]
  assert_output_contains "single file"
}

@test "the single file and the modular build give the same --help and completion" {
  local dir="$BATS_TEST_TMPDIR/b" cmd
  build_bundle "$dir"
  for cmd in chromebrew powerwash rootfs rw cbs-check chromebrew-scripts; do
    diff <("$REPO_ROOT/bin/$cmd" --help) <("$dir/$cmd" --help)
  done
  diff "$REPO_ROOT/completions/chromebrew-scripts.bash" <("$dir/chromebrew-scripts" --completion bash)
  diff <("$REPO_ROOT/bin/chromebrew-scripts" --completion bash) <("$dir/rw" --completion bash)
}

@test "the modular entry point refuses to run without its modules" {
  local dir="$BATS_TEST_TMPDIR/broken"
  mkdir -p "$dir/bin"
  cp "$REPO_ROOT/bin/chromebrew-scripts" "$dir/bin/"
  run "$dir/bin/chromebrew-scripts" --version
  [ "$status" -ne 0 ]
}
