#!/usr/bin/env bats
# tests/unit/completion.bats - the bash completion script, and that its
# option lists stay in step with the commands.

load ../test_helper

setup() {
  setup_sandbox
  # shellcheck disable=SC1091
  source "$REPO_ROOT/completions/chromebrew-scripts.bash"
}

# complete_words WORD...: run the completion function for the given command
# line (the cursor on the last word) and print COMPREPLY.
complete_words() {
  local COMP_WORDS=("$@") COMP_CWORD=$(($# - 1)) COMPREPLY=()
  _chromebrew_scripts
  printf '%s\n' "${COMPREPLY[@]}"
}

@test "completes the command names and the common options after chromebrew-scripts" {
  run complete_words chromebrew-scripts ""
  assert_output_contains "powerwash"
  assert_output_contains "check"
  assert_output_contains "--self-update"
  assert_output_contains "--completion"
  run complete_words chromebrew-scripts po
  [ "$output" = powerwash ]
}

@test "completes a command's own options after the command or under its own name" {
  run complete_words chromebrew-scripts rw --u
  [ "$output" = "--undo" ]
  run complete_words rw --
  assert_output_contains "--undo"
  assert_output_contains "--ro"
  assert_output_contains "--dry-run"
  run complete_words cbs-check --o
  [ "$output" = "--offline" ]
  run complete_words chromebrew-scripts check --o
  [ "$output" = "--offline" ]
  run complete_words rootfs --no
  assert_output_contains "--no-reboot"
  assert_output_contains "--no-color"
  run complete_words chromebrew --re
  [ "$output" = $'--remove\n--restore' ]
}

@test "completes option values" {
  run complete_words chromebrew --color ""
  [ "$output" = $'auto\nalways\nnever' ]
  run complete_words chromebrew-scripts --color=al
  [ "$output" = "--color=always" ]
  run complete_words chromebrew-scripts --completion ""
  [ "$output" = $'bash\nzsh' ]
  run complete_words rw --timeout ""
  [ -z "$output" ]
  touch "$BATS_TEST_TMPDIR/some.conf"
  cd "$BATS_TEST_TMPDIR"
  run complete_words rw --config som
  [ "$output" = some.conf ]
}

@test "the completion's option lists match each command's options and the common options" {
  load_cbs
  local cmd want have opt
  for cmd in chromebrew powerwash rootfs rw check; do
    want=$("cmd_${cmd}_options" | sort | tr '\n' ' ')
    have=$(_cbs_cmd_opts "$cmd" | tr ' ' '\n' | sort | tr '\n' ' ')
    assert_equal "$want" "$have"
    for opt in $want; do
      [ "$opt" = -- ] && continue
      "cmd_${cmd}_usage" | grep -qF -- "$opt" || {
        echo "$cmd --help does not mention $opt"
        return 1
      }
    done
  done
  want=$(args_common_usage | grep -o -- '--[a-z][a-z-]*' | sort -u | tr '\n' ' ')
  # shellcheck disable=SC2086,SC2154  # the list is split on purpose
  have=$(printf '%s\n' $_cbs_common_opts | sort -u | tr '\n' ' ')
  assert_equal "$want" "$have"
  # every command name is completed
  for cmd in "${CBS_COMMANDS[@]}"; do
    # shellcheck disable=SC2154
    [[ " $_cbs_commands " == *" $cmd "* ]]
  done
}
