#!/usr/bin/env bats
# tests/unit/config.bats - settings: config files, environment, flags, their
# precedence, and that a config file is parsed and never executed.

load ../test_helper

setup() { setup_sandbox; }

@test "settings: default < system file < user file < environment < flag" {
  run "$CBS_BIN_DIR/cbs-check" --offline
  [ "$status" -eq 0 ]
  assert_output_contains "Settings (non-default): (defaults)"
  printf 'TIMEOUT=11\nCREW_TIMEOUT=100\n' > "$CBS_SYSTEM_CONFIG"
  run "$CBS_BIN_DIR/cbs-check" --offline
  [ "$status" -eq 0 ]
  assert_output_contains "TIMEOUT=11 ($CBS_SYSTEM_CONFIG:1)"
  assert_output_contains "CREW_TIMEOUT=100 ($CBS_SYSTEM_CONFIG:2)"
  mkdir -p "$CBS_HOME/.config/chromebrew-scripts"
  printf '# user\nTIMEOUT = "22"\n' > "$CBS_HOME/.config/chromebrew-scripts/config"
  run "$CBS_BIN_DIR/cbs-check" --offline
  [ "$status" -eq 0 ]
  assert_output_contains "TIMEOUT=22 ($CBS_HOME/.config/chromebrew-scripts/config:2)"
  assert_output_contains "CREW_TIMEOUT=100 ($CBS_SYSTEM_CONFIG:2)"
  run env TIMEOUT=33 "$CBS_BIN_DIR/cbs-check" --offline
  [ "$status" -eq 0 ]
  assert_output_contains "TIMEOUT=33 (env)"
  run env TIMEOUT=33 "$CBS_BIN_DIR/cbs-check" --offline --timeout 44
  [ "$status" -eq 0 ]
  assert_output_contains "TIMEOUT=44 (flag)"
  run env XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/xdg" "$CBS_BIN_DIR/cbs-check" --offline
  [ "$status" -eq 0 ]
  assert_output_contains "TIMEOUT=11 ($CBS_SYSTEM_CONFIG:1)"
  assert_output_contains "Config:                $BATS_TEST_TMPDIR/xdg/chromebrew-scripts/config (absent)"
}

@test "settings: --config FILE replaces the user file; a missing one warns" {
  mkdir -p "$CBS_HOME/.config/chromebrew-scripts"
  printf 'TIMEOUT=22\n' > "$CBS_HOME/.config/chromebrew-scripts/config"
  printf 'LOG_KEEP=3\n' > "$BATS_TEST_TMPDIR/alt.conf"
  run "$CBS_BIN_DIR/cbs-check" --offline --config "$BATS_TEST_TMPDIR/alt.conf"
  [ "$status" -eq 0 ]
  assert_output_contains "LOG_KEEP=3 ($BATS_TEST_TMPDIR/alt.conf:1)"
  assert_output_not_contains "TIMEOUT=22"
  run "$CBS_BIN_DIR/cbs-check" --offline --config "$BATS_TEST_TMPDIR/nope.conf"
  [ "$status" -eq 0 ]
  assert_output_contains "config file not readable: $BATS_TEST_TMPDIR/nope.conf"
}

@test "settings: unknown keys, bad values and shell syntax are ignored and never executed" {
  cat > "$CBS_SYSTEM_CONFIG" <<EOF
TIMEOUT=\$(touch $SANDBOX/pwned-1)
CREW_PREFIX=\`touch $SANDBOX/pwned-2\`
touch $SANDBOX/pwned-3
SELF_UPDATE_REPO=http://example.test/insecure
COLOR=sometimes
NOT_A_KEY=1
LOG_DIR=relative/path
LOGGING=no
EOF
  run "$CBS_BIN_DIR/cbs-check" --offline
  [ "$status" -eq 0 ]
  [ ! -e "$SANDBOX/pwned-1" ]
  [ ! -e "$SANDBOX/pwned-2" ]
  [ ! -e "$SANDBOX/pwned-3" ]
  assert_output_contains "invalid value for TIMEOUT ($CBS_SYSTEM_CONFIG:1) ignored"
  assert_output_contains "invalid value for CREW_PREFIX ($CBS_SYSTEM_CONFIG:2) ignored"
  assert_output_contains "$CBS_SYSTEM_CONFIG:3: not a KEY=value line, ignored"
  assert_output_contains "invalid value for SELF_UPDATE_REPO ($CBS_SYSTEM_CONFIG:4) ignored"
  assert_output_contains "invalid value for COLOR ($CBS_SYSTEM_CONFIG:5) ignored"
  assert_output_contains "unknown key 'NOT_A_KEY' ($CBS_SYSTEM_CONFIG:6) ignored"
  assert_output_contains "invalid value for LOG_DIR ($CBS_SYSTEM_CONFIG:7) ignored"
  assert_output_contains "Settings (non-default): LOGGING=0 ($CBS_SYSTEM_CONFIG:8)"
  assert_output_contains "off (LOGGING=0)"
  [ -z "$(log_files)" ]
}

@test "settings: a bad value from the environment or a flag" {
  run env TIMEOUT=soon "$CBS_BIN_DIR/cbs-check" --offline
  [ "$status" -eq 0 ]
  assert_output_contains "invalid value for TIMEOUT (env) ignored"
  assert_output_contains "Settings (non-default): (defaults)"
  run "$CBS_BIN_DIR/cbs-check" --offline --timeout soon
  [ "$status" -eq 2 ]
  assert_output_contains "invalid value for TIMEOUT (flag) ignored"
  run "$CBS_BIN_DIR/rw" -ny --source http://example.test/repo
  [ "$status" -eq 2 ]
  assert_output_contains "invalid value for SELF_UPDATE_REPO (flag) ignored"
  [ -z "$(calls | grep -v '^crew ')" ]  # only crew --version is read
}

@test "settings: the 2.0.0 environment names still work and the current names win" {
  run env CBS_CREW_TIMEOUT=7 CBS_CURL_TIMEOUT=9 CBS_PREFIX=/opt/crew CREW_FORCE_INSTALL=1 CBS_REF=dev \
    "$CBS_BIN_DIR/cbs-check" --offline
  [ "$status" -eq 0 ]
  assert_output_contains "CREW_TIMEOUT=7 (env CBS_CREW_TIMEOUT)"
  assert_output_contains "DOWNLOAD_TIMEOUT=9 (env CBS_CURL_TIMEOUT)"
  assert_output_contains "CREW_PREFIX=/opt/crew (env CBS_PREFIX)"
  assert_output_contains "FORCE_INSTALL=1 (env CREW_FORCE_INSTALL)"
  assert_output_contains "SELF_UPDATE_BRANCH=dev (env CBS_REF)"
  [[ "$output" =~ Chromebrew\ prefix:[[:space:]]+/opt/crew ]]
  run env CBS_CREW_TIMEOUT=7 CREW_TIMEOUT=8 "$CBS_BIN_DIR/cbs-check" --offline
  [ "$status" -eq 0 ]
  assert_output_contains "CREW_TIMEOUT=8 (env)"
  assert_output_not_contains "CBS_CREW_TIMEOUT"
  run env CBS_REPO=someone/fork "$CBS_BIN_DIR/cbs-check" --offline
  [ "$status" -eq 0 ]
  assert_output_contains "SELF_UPDATE_REPO=https://github.com/someone/fork (env CBS_REPO)"
  run env CBS_REPO=https://example.test/x.git SELF_UPDATE_REPO=https://example.test/y "$CBS_BIN_DIR/cbs-check" --offline
  [ "$status" -eq 0 ]
  assert_output_contains "SELF_UPDATE_REPO=https://example.test/y (env)"
}

@test "settings: the toolkit's own defaults are not mistaken for environment overrides" {
  run "$CBS_BIN_DIR/cbs-check" --offline
  [ "$status" -eq 0 ]
  assert_output_contains "Settings (non-default): (defaults)"
}

@test "config_parse_file: whitespace, quotes and booleans" {
  load_cbs
  printf '  LOG_KEEP = 5 \nCOLOR="never"\nLOGGING=%s\nFORCE_INSTALL=Yes\nMIN_FREE_MB=0\n' "'off'" > "$BATS_TEST_TMPDIR/c"
  config_parse_file "$BATS_TEST_TMPDIR/c"
  [ "$(cfg LOG_KEEP)" = 5 ]
  [ "$(cfg COLOR)" = never ]
  [ "$(cfg LOGGING)" = 0 ]
  [ "$(cfg FORCE_INSTALL)" = 1 ]
  [ "$(cfg MIN_FREE_MB)" = 0 ]
  cfg_bool FORCE_INSTALL
  ! cfg_bool LOGGING
  [ "${CBS_CFG_SOURCE[LOG_KEEP]}" = "$BATS_TEST_TMPDIR/c:1" ]
  [ "${CBS_CFG_SOURCE[TIMEOUT]}" = default ]
}

@test "config_valid: the value classes" {
  load_cbs
  config_valid int 0 && config_valid int 300 && ! config_valid int -1 && ! config_valid int 1.5 && ! config_valid int 1234567890
  config_valid bool on && config_valid bool FALSE && ! config_valid bool maybe
  config_valid url https://github.com/a/b && ! config_valid url http://github.com/a/b && ! config_valid url 'https://x/$(y)'
  config_valid path /var/log/x && config_valid path "" && ! config_valid path relative && ! config_valid path /a/../b && ! config_valid path '/a b'
  config_valid name main && config_valid name release/2.1 && ! config_valid name ../x && ! config_valid name -x
  config_valid color auto && ! config_valid color blue
  ! config_valid int $'1\n2'
}
