#!/usr/bin/env bats
# tests/unit/args.bats - the shared command line parser and colours/icons.

load ../test_helper

setup() { setup_sandbox; }

@test "args_parse splits combined short flags and --opt=value, keeps the rest for the command" {
  load_cbs
  args_parse -ny --timeout=7 --color=never rest --undo -q
  [ "$CBS_ARG_DRY_RUN" = 1 ]
  [ "$CBS_ARG_YES" = 1 ]
  [ "$CBS_ARG_QUIET" = 1 ]
  [ "$CBS_ARG_TIMEOUT" = 7 ]
  [ "$CBS_ARG_COLOR" = never ]
  [ "${CBS_CMD_ARGS[*]}" = "rest --undo" ]
}

@test "args_parse keeps everything after -- for the command" {
  load_cbs
  args_parse -n -- --partitions 2 -y
  [ "$CBS_ARG_DRY_RUN" = 1 ]
  [ -z "$CBS_ARG_YES" ]
  # the "--" stays: rootfs passes what follows it to make_dev_ssd.sh
  [ "${CBS_CMD_ARGS[*]}" = "-- --partitions 2 -y" ]
}

@test "args_parse: --no-log and --log, --self-update with --source and --branch, --version, --completion" {
  load_cbs
  args_parse --log /tmp/x.log
  [ "$CBS_LOG_PATH" = /tmp/x.log ] && [ "$CBS_ARG_LOGGING" = 1 ]
  args_parse --no-log
  [ -z "$CBS_LOG_PATH" ] && [ "$CBS_ARG_LOGGING" = 0 ]
  args_parse --self-update --source https://example.test/r --branch dev
  [ "$CBS_ARG_SELF_UPDATE" = 1 ] && [ "$CBS_ARG_SOURCE" = https://example.test/r ] && [ "$CBS_ARG_BRANCH" = dev ]
  args_parse -V
  [ "$CBS_ARG_VERSION" = 1 ]
  args_parse --completion bash
  [ "$CBS_ARG_COMPLETION" = bash ]
}

@test "args_parse fails with 2 on a missing value" {
  load_cbs
  local opt
  for opt in --timeout --color --config --log --source --branch --completion; do
    run_fn args_parse "$opt"
    [ "$status" -eq 2 ]
    assert_output_contains "option $opt requires a value"
  done
}

@test "args_apply layers the flags over the settings" {
  load_cbs
  args_parse --timeout 9 --no-color --branch dev -v -q
  args_apply
  [ "$(cfg TIMEOUT)" = 9 ] && [ "${CBS_CFG_SOURCE[TIMEOUT]}" = flag ]
  [ "$CBS_TIMEOUT" = 9 ]
  [ "$CBS_COLOR" = never ]
  [ "$(cfg SELF_UPDATE_BRANCH)" = dev ]
  # --verbose wins over --quiet
  [ "$CBS_VERBOSE" = 1 ] && [ "$CBS_QUIET" = 0 ]
  args_parse --timeout nope
  run_fn args_apply
  [ "$status" -eq 2 ]
}

@test "--completion prints the bash completion script; other shells are refused" {
  run "$CBS_BIN_DIR/chromebrew-scripts" --completion bash
  [ "$status" -eq 0 ]
  assert_output_contains "complete -F _chromebrew_scripts chromebrew-scripts chromebrew powerwash rootfs rw cbs-check"
  run "$CBS_BIN_DIR/rw" --completion fish
  [ "$status" -eq 2 ]
  assert_output_contains "--completion supports bash"
  [ -z "$(log_files)" ]
}

@test "colours: off when not a terminal, on with --color always or COLOR=always, off with --no-color" {
  run "$CBS_BIN_DIR/rw" -ny
  [ "$status" -eq 0 ]
  assert_output_not_contains $'\033['
  run env -u NO_COLOR "$CBS_BIN_DIR/rw" -ny --color always
  [ "$status" -eq 0 ]
  assert_output_contains $'\033[1m'
  run env -u NO_COLOR COLOR=always "$CBS_BIN_DIR/rw" -ny
  [ "$status" -eq 0 ]
  assert_output_contains $'\033['
  run env -u NO_COLOR COLOR=always "$CBS_BIN_DIR/rw" -ny --no-color
  [ "$status" -eq 0 ]
  assert_output_not_contains $'\033['
  run env NO_COLOR=1 "$CBS_BIN_DIR/rw" -ny --color auto
  [ "$status" -eq 0 ]
  assert_output_not_contains $'\033['
  run "$CBS_BIN_DIR/rw" -ny --color sometimes
  [ "$status" -eq 2 ]
  assert_output_contains "invalid value for COLOR (flag) ignored"
}

@test "icons are Unicode in a UTF-8 locale and ASCII otherwise" {
  run env LC_ALL=C.UTF-8 "$CBS_BIN_DIR/rw" -y
  [ "$status" -eq 0 ]
  assert_output_contains "↑ remount $SANDBOX read/write: remounted rw"
  run env LC_ALL=C LANG=C LC_CTYPE=C "$CBS_BIN_DIR/rw" -y
  [ "$status" -eq 0 ]
  assert_output_contains "UP remount $SANDBOX read/write: remounted rw"
  assert_output_not_contains "↑"
}
