#!/usr/bin/env bats
# tests/unit/install.bats - install.sh: the single-file and tree layouts,
# --uninstall, --update and the clean-up of older layouts.

load ../test_helper

setup() {
  setup_sandbox
  PREFIX_DIR="$BATS_TEST_TMPDIR/prefix"
  export CBS_SUDO=
}

version() { tr -d '[:space:]' < "$REPO_ROOT/VERSION"; }

@test "install.sh installs the single file and the command symlinks" {
  run bash "$REPO_ROOT/install.sh" --prefix "$PREFIX_DIR"
  [ "$status" -eq 0 ]
  assert_output_contains "installed chromebrew-scripts $(version) (single file) to $PREFIX_DIR/bin/chromebrew-scripts"
  grep -q '^CBS_BUNDLED=1$' "$PREFIX_DIR/bin/chromebrew-scripts"
  [ -x "$PREFIX_DIR/bin/chromebrew-scripts" ]
  local cmd
  for cmd in chromebrew powerwash rootfs rw cbs-check; do
    [ -L "$PREFIX_DIR/bin/$cmd" ]
    [ "$(readlink "$PREFIX_DIR/bin/$cmd")" = chromebrew-scripts ]
  done
  [ -f "$PREFIX_DIR/share/bash-completion/completions/chromebrew-scripts" ]
  [ ! -e "$PREFIX_DIR/share/chromebrew-scripts" ]
  run "$PREFIX_DIR/bin/rw" --version
  [ "$status" -eq 0 ]
  [[ "$output" == "chromebrew-scripts $(version) (git "*", single file)" ]]
  run "$PREFIX_DIR/bin/rw" -ny
  [ "$status" -eq 0 ]
  assert_output_contains "would run: mount -o remount,rw $SANDBOX"
}

@test "install.sh --tree installs the checkout and links the commands into it" {
  run bash "$REPO_ROOT/install.sh" --tree --prefix "$PREFIX_DIR"
  [ "$status" -eq 0 ]
  assert_output_contains "installed chromebrew-scripts $(version) (tree) to $PREFIX_DIR/share/chromebrew-scripts"
  [ -f "$PREFIX_DIR/share/chromebrew-scripts/bin/chromebrew-scripts" ]
  [ -d "$PREFIX_DIR/share/chromebrew-scripts/lib/core" ]
  [ -e "$PREFIX_DIR/share/chromebrew-scripts/.git" ]
  [ "$(readlink "$PREFIX_DIR/bin/rw")" = "$PREFIX_DIR/share/chromebrew-scripts/bin/chromebrew-scripts" ]
  [ "$(readlink "$PREFIX_DIR/bin/chromebrew-scripts")" = "$PREFIX_DIR/share/chromebrew-scripts/bin/chromebrew-scripts" ]
  [ -L "$PREFIX_DIR/share/bash-completion/completions/chromebrew-scripts" ]
  run "$PREFIX_DIR/bin/cbs-check" --version
  [ "$status" -eq 0 ]
  [[ "$output" == "chromebrew-scripts $(version)"* ]]
  [[ "$output" != *"single file"* ]]
  run "$PREFIX_DIR/bin/powerwash" -ny
  [ "$status" -eq 0 ]
  assert_output_contains "would run: reboot"
}

@test "install.sh switches between the layouts, removing the other one" {
  bash "$REPO_ROOT/install.sh" --prefix "$PREFIX_DIR" >/dev/null
  run bash "$REPO_ROOT/install.sh" --tree --prefix "$PREFIX_DIR"
  [ "$status" -eq 0 ]
  assert_output_contains "removed the previous single file $PREFIX_DIR/bin/chromebrew-scripts"
  [ -L "$PREFIX_DIR/bin/chromebrew-scripts" ]
  run bash "$REPO_ROOT/install.sh" --prefix "$PREFIX_DIR"
  [ "$status" -eq 0 ]
  assert_output_contains "removed the previous tree installation $PREFIX_DIR/share/chromebrew-scripts"
  [ ! -e "$PREFIX_DIR/share/chromebrew-scripts" ]
  [ -f "$PREFIX_DIR/bin/chromebrew-scripts" ]
  [ ! -L "$PREFIX_DIR/bin/chromebrew-scripts" ]
  [ "$(readlink "$PREFIX_DIR/bin/rw")" = chromebrew-scripts ]
  [ -f "$PREFIX_DIR/share/bash-completion/completions/chromebrew-scripts" ]
  [ ! -L "$PREFIX_DIR/share/bash-completion/completions/chromebrew-scripts" ]
}

@test "install.sh replaces a 2.0.0 tree installation" {
  local share="$PREFIX_DIR/share/chromebrew-scripts" cmd
  mkdir -p "$share/bin" "$share/lib" "$PREFIX_DIR/bin"
  touch "$share/bin/chromebrew" "$share/lib/common.sh"
  for cmd in chromebrew powerwash rootfs rw; do
    ln -s "../share/chromebrew-scripts/bin/$cmd" "$PREFIX_DIR/bin/$cmd"
  done
  run bash "$REPO_ROOT/install.sh" --prefix "$PREFIX_DIR"
  [ "$status" -eq 0 ]
  assert_output_contains "removed the previous tree installation $share"
  [ ! -e "$share" ]
  [ "$(readlink "$PREFIX_DIR/bin/rw")" = chromebrew-scripts ]
  run "$PREFIX_DIR/bin/rw" --version
  [ "$status" -eq 0 ]
}

@test "install.sh leaves files that are not ours alone, installing and uninstalling" {
  mkdir -p "$PREFIX_DIR/bin" "$PREFIX_DIR/share/bash-completion/completions"
  echo "#!/bin/sh" > "$PREFIX_DIR/bin/rw"
  echo "# somebody else's completion" > "$PREFIX_DIR/share/bash-completion/completions/chromebrew-scripts"
  run bash "$REPO_ROOT/install.sh" --prefix "$PREFIX_DIR"
  [ "$status" -eq 0 ]
  assert_output_contains "$PREFIX_DIR/bin/rw exists and is not a symlink; left alone"
  assert_output_contains "is not ours; bash completion not installed"
  [ "$(cat "$PREFIX_DIR/bin/rw")" = "#!/bin/sh" ]
  [ -L "$PREFIX_DIR/bin/powerwash" ]
  run bash "$REPO_ROOT/install.sh" --uninstall --prefix "$PREFIX_DIR"
  [ "$status" -eq 0 ]
  assert_output_contains "$PREFIX_DIR/bin/rw is not a symlink; left alone"
  assert_output_contains "is not ours; left alone"
  [ -f "$PREFIX_DIR/bin/rw" ]
  [ "$(cat "$PREFIX_DIR/share/bash-completion/completions/chromebrew-scripts")" = "# somebody else's completion" ]
  [ ! -e "$PREFIX_DIR/bin/chromebrew-scripts" ]
  [ ! -e "$PREFIX_DIR/bin/powerwash" ]
}

@test "install.sh --uninstall removes everything it installed, in both layouts" {
  bash "$REPO_ROOT/install.sh" --prefix "$PREFIX_DIR" >/dev/null
  run bash "$REPO_ROOT/install.sh" --uninstall --prefix "$PREFIX_DIR"
  [ "$status" -eq 0 ]
  assert_output_contains "removed $PREFIX_DIR/bin/chromebrew-scripts"
  [ -z "$(ls -A "$PREFIX_DIR/bin")" ]
  [ ! -e "$PREFIX_DIR/share/bash-completion/completions/chromebrew-scripts" ]
  bash "$REPO_ROOT/install.sh" --tree --prefix "$PREFIX_DIR" >/dev/null
  run bash "$REPO_ROOT/install.sh" --uninstall --prefix "$PREFIX_DIR"
  [ "$status" -eq 0 ]
  assert_output_contains "removed $PREFIX_DIR/share/chromebrew-scripts"
  [ -z "$(ls -A "$PREFIX_DIR/bin")" ]
  [ ! -e "$PREFIX_DIR/share/chromebrew-scripts" ]
  run bash "$REPO_ROOT/install.sh" --uninstall --prefix "$PREFIX_DIR"
  [ "$status" -eq 0 ]
  assert_output_contains "nothing of chromebrew-scripts found"
}

@test "install.sh --user installs under ~/.local" {
  run bash "$REPO_ROOT/install.sh" --user
  [ "$status" -eq 0 ]
  [ -f "$CBS_HOME/.local/bin/chromebrew-scripts" ]
  [ "$(readlink "$CBS_HOME/.local/bin/rw")" = chromebrew-scripts ]
  [ -f "$CBS_HOME/.local/share/bash-completion/completions/chromebrew-scripts" ]
  run "$CBS_HOME/.local/bin/cbs-check" --offline
  [ "$status" -eq 0 ]
  run bash "$REPO_ROOT/install.sh" --user --uninstall
  [ "$status" -eq 0 ]
  [ ! -e "$CBS_HOME/.local/bin/chromebrew-scripts" ]
  [ ! -e "$CBS_HOME/.local/bin/rw" ]
}

@test "install.sh --update downloads the branch tarball and reinstalls (CBS_REPO, CBS_REF)" {
  run env CBS_REPO=someone/fork CBS_REF=main bash "$REPO_ROOT/install.sh" --update --prefix "$PREFIX_DIR"
  [ "$status" -eq 0 ]
  assert_output_contains "downloading https://github.com/someone/fork/archive/refs/heads/main.tar.gz"
  assert_called "curl -fsSL --proto =https,file --proto-redir =https --retry 2 --connect-timeout 20 --max-time 300 -o"
  assert_called "https://github.com/someone/fork/archive/refs/heads/main.tar.gz"
  grep -q '^CBS_BUNDLED=1$' "$PREFIX_DIR/bin/chromebrew-scripts"
  run "$PREFIX_DIR/bin/rw" --version
  [ "$status" -eq 0 ]
  [[ "$output" == "chromebrew-scripts $(version) (git unknown, single file)" ]]
}

@test "install.sh --update reads SELF_UPDATE_REPO from the config files; the environment wins" {
  printf 'SELF_UPDATE_REPO=https://github.com/from/system\nSELF_UPDATE_BRANCH=sys\nDOWNLOAD_TIMEOUT=77\n' > "$CBS_SYSTEM_CONFIG"
  run bash "$REPO_ROOT/install.sh" --update --prefix "$PREFIX_DIR"
  [ "$status" -eq 0 ]
  assert_called "--max-time 77 -o"
  assert_called "https://github.com/from/system/archive/refs/heads/sys.tar.gz"
  mkdir -p "$CBS_HOME/.config/chromebrew-scripts"
  printf '# user config\nSELF_UPDATE_REPO = "https://github.com/from/user"\n' > "$CBS_HOME/.config/chromebrew-scripts/config"
  : > "$STUB_LOG"
  run bash "$REPO_ROOT/install.sh" --update --prefix "$PREFIX_DIR"
  [ "$status" -eq 0 ]
  assert_called "https://github.com/from/user/archive/refs/heads/sys.tar.gz"
  : > "$STUB_LOG"
  run env SELF_UPDATE_REPO=https://github.com/from/env CBS_REPO=x/y SELF_UPDATE_BRANCH=env \
    bash "$REPO_ROOT/install.sh" --update --prefix "$PREFIX_DIR"
  [ "$status" -eq 0 ]
  assert_called "https://github.com/from/env/archive/refs/heads/env.tar.gz"
}

@test "install.sh --update refuses a source that is not https" {
  run env CBS_TARBALL_URL=http://example.test/x.tar.gz bash "$REPO_ROOT/install.sh" --update --prefix "$PREFIX_DIR"
  [ "$status" -eq 1 ]
  assert_output_contains "refusing a non-https source"
  assert_not_called curl
  [ ! -e "$PREFIX_DIR/bin/chromebrew-scripts" ]
  printf 'SELF_UPDATE_REPO=http://example.test/repo\nSELF_UPDATE_BRANCH=main\n' > "$CBS_SYSTEM_CONFIG"
  run bash "$REPO_ROOT/install.sh" --update --prefix "$PREFIX_DIR"
  [ "$status" -eq 0 ]
  # the bad value is ignored and the default repository used
  assert_called "https://github.com/uberhacker/chromebrew-scripts/archive/refs/heads/main.tar.gz"
}

@test "install.sh --update keeps a tree installation a tree" {
  bash "$REPO_ROOT/install.sh" --tree --prefix "$PREFIX_DIR" >/dev/null
  run env SELF_UPDATE_BRANCH=main bash "$REPO_ROOT/install.sh" --update --prefix "$PREFIX_DIR"
  [ "$status" -eq 0 ]
  assert_output_contains "keeping the tree layout"
  [ -L "$PREFIX_DIR/bin/chromebrew-scripts" ]
  [ -f "$PREFIX_DIR/share/chromebrew-scripts/bin/chromebrew-scripts" ]
  run env SELF_UPDATE_BRANCH=main bash "$REPO_ROOT/install.sh" --update --single --prefix "$PREFIX_DIR"
  [ "$status" -eq 0 ]
  [ -f "$PREFIX_DIR/bin/chromebrew-scripts" ]
  [ ! -L "$PREFIX_DIR/bin/chromebrew-scripts" ]
  [ ! -e "$PREFIX_DIR/share/chromebrew-scripts" ]
}

@test "install.sh rejects unknown options and a missing --prefix value" {
  run bash "$REPO_ROOT/install.sh" --bogus
  [ "$status" -eq 2 ]
  assert_output_contains "unknown option: --bogus"
  run bash "$REPO_ROOT/install.sh" --prefix
  [ "$status" -eq 1 ]
  assert_output_contains "--prefix needs a directory"
  run bash "$REPO_ROOT/install.sh" --help
  [ "$status" -eq 0 ]
  assert_output_contains "./install.sh --tree"
  [ ! -e "$PREFIX_DIR" ]
}
