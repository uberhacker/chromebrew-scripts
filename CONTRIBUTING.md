# Contributing to chromebrew-scripts

Thanks for helping. Fixes, better probes for `cbs-check`, and reports of what
a command printed on a real device are all welcome: open an issue or a pull
request and say which ChromeOS release and channel you saw it on
(`cbs-check` prints everything useful).

## Before you start

You need bash 4.4 or later, coreutils, `shellcheck` and `git`.
[bats-core](https://github.com/bats-core/bats-core) is fetched into
`tests/vendor/` on first use when it is not installed.

```
tests/lint.sh            # bash -n on every script, shellcheck -x on the sources and on a single-file build
tests/run.sh             # the bats suite, against bin/ and against a fresh single-file build
tests/run.sh --filter rw # a subset (arguments go to bats); CBS_TEST_TARGET=modular|bundle runs one build
tests/install-smoke.sh   # install.sh end to end into a temporary prefix
./build.sh               # the single-file build, dist/chromebrew-scripts
```

CI runs all of them on every push and pull request (`.github/workflows/ci.yml`:
lint, the unit tests against both builds with bats-core pinned to a release
commit, the single-file build as an artifact, and the install smoke test in
`debian:stable-slim` and `alpine:3` containers). Please run at least
`tests/lint.sh` and `tests/run.sh` before you open a pull request.

Nothing in the tests touches the real system, and nothing in a pull request
should need to: every path goes through `CBS_ROOT`, every external program
goes through a stub. A change that can only be checked on a device is fine,
but say so, and say what you saw.

## How the program fits together

```
bin/chromebrew-scripts        the entry point
bin/<command>                 symlinks to it (chromebrew, powerwash, rootfs, rw, cbs-check)
lib/core/*.sh                 shared modules, sourced in a fixed order
lib/cmd/<command>.sh          one module per command
completions/chromebrew-scripts.bash
build.sh                      inlines the modules into one file
```

The entry point works out which command to run from the name it was called
by (a symlink), or from its first argument when called as
`chromebrew-scripts`; `cbs-check` maps to the `check` command. It then
parses the common options (`lib/core/args.sh`), loads the configuration
(`lib/core/config.sh`), opens the run log (`lib/core/runlog.sh`), and hands
the remaining arguments to the command module.

The core modules, in the order they are sourced:

| Module | What it holds |
| --- | --- |
| `log.sh` | colours, icons, `log_info`/`log_warn`/`log_error`/`log_ok`/`log_updated`/`log_dry`/`log_cmd`/`log_kv`/`log_plain`, the console descriptor `CBS_OUT`, and the copy of every line into the run log |
| `util.sh` | the runners (`run`, `run_sudo`, `do_run`, `do_sudo`, `do_pipe`, `yes_pipe`), `confirm`, `download` (https only) and `verify_sha256`, `tmp_dir`, `has_cmd`, `is_root`, `rc_note`, `cbs_quote`, `human_mb` (`version_string` lives in the entry point) |
| `config.sh` | the whitelist of keys with defaults and types, the file parser, precedence, `cfg`/`cfg_bool` |
| `args.sh` | `args_parse` for the common options, `args_apply`, `args_common_usage` |
| `chromeos.sh` | the read-only probes: lsb-release, channel, `crossystem`, `/proc/cmdline`, `/proc/mounts`, `df`, Crostini; every `CBS_*` path |
| `crew.sh` | `crew_bin`, `crew_version`, `crew_installed`, `crew_timeout_prefix` |
| `runner.sh` | `run_step`, `step_ok`/`step_updated`/`step_skip`/`step_dry`/`step_warn`/`step_fail`, the summary and the exit status |
| `runlog.sh` | where the log goes, its header and footer, pruning |
| `selfupdate.sh` | `--self-update` for a git checkout, a tree and a single file |

## Adding a command

A command is one module in `lib/cmd/`, one symlink in `bin/`, one page in
`docs/`, one test file in `tests/unit/`, and four one-line additions.

### 1. The module: `lib/cmd/<name>.sh`

```bash
#!/usr/bin/env bash
# lib/cmd/foo.sh - what foo does, in one line, and anything surprising.

CBS_FOO_FAST=0

cmd_foo_usage() {
  cat <<EOF
Usage: foo [options]

What foo does, what it changes, and what it needs.

Options:
      --fast              skip the slow part

EOF
  args_common_usage
}

cmd_foo_options() { printf '%s\n' --fast; }

cmd_foo_parse() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --fast) CBS_FOO_FAST=1 ;;
      *) log_error "unknown option: $1"; return 2 ;;
    esac
    shift
  done
  return 0
}

foo_step_thing() {
  local rc=0
  do_sudo some-command --flag "$CBS_STATEFUL/file" || rc=$?
  if [ "$rc" -ne 0 ]; then
    step_fail "some-command failed ($(rc_note "$rc"))"
    return 1
  fi
  if [ "$CBS_DRY_RUN" = 1 ]; then step_dry "would do the thing"; else step_updated "thing done"; fi
}

cmd_foo_run() {
  require_chromeos || return 1
  confirm "Are you sure you want to do the thing?" || return 1
  run_step "do the thing" foo_step_thing || return 1
  return 0
}
```

| Function | Required | What it does |
| --- | --- | --- |
| `cmd_<name>_usage` | yes | prints the help text, ending with `args_common_usage` so the common options are documented once |
| `cmd_<name>_options` | yes | prints the command's own options, one per line; the completion test checks them against `--help` and the completion file |
| `cmd_<name>_parse "$@"` | yes | parses the command's own options (the common ones are already gone); returns 2 with a `log_error` on a usage error |
| `cmd_<name>_run` | yes | the command: guards, the confirmation, then `run_step` per step; returns 1 after a failed step so that nothing later runs |

### 2. Wire it up

1. `ln -s chromebrew-scripts bin/<name>` (a `cbs-` prefix if the bare name is
   taken by something common, as `cbs-check` is).
2. Add the name to `CBS_COMMANDS` in `bin/chromebrew-scripts` (and to
   `command_from_name` if the file name differs from the command name), and
   `source` the module where the others are sourced; `build.sh` picks the
   module list up from those `source` lines.
3. Add the name to `COMMANDS` in `install.sh`, to `_cbs_commands` and
   `_cbs_cmd_opts` in `completions/chromebrew-scripts.bash` (the completion
   test fails until the lists agree), to the `complete -F` line there, and
   to the loop in `tests/unit/completion.bats`.
4. Write `docs/<name>.md` (copy the page of the command most like it and keep
   its sections: the summary table, What it does, What will be affected,
   Dry run, Unattended use, Troubleshooting, Not verified here) and add a
   row to the tables in `docs/README.md` and `README.md`.

### 3. Rules every module follows

- **No `set -e`.** The toolkit runs with `set -uo pipefail` only; a step
  handles its own errors and reports exactly one result through `step_ok`,
  `step_updated`, `step_skip`, `step_dry`, `step_warn` or `step_fail`. A
  step that returns non-zero without reporting is recorded as failed.
- **Everything that changes something goes through a runner**, never
  directly: `do_run` / `do_sudo` for a command, `do_pipe DESC FUNC` for a
  pipeline wrapped in a function (`echo clobber | sudo tee ...`). In a dry
  run they print `would run: ...` and do nothing; otherwise they run the
  command with stdin closed, under `TIMEOUT` (`CBS_RUN_TIMEOUT` for one
  call; `CREW_TIMEOUT` through `crew_timeout_prefix`), and copy its output
  into the run log. `run` / `run_sudo` are for read-only commands that should
  run in a dry run too.
- **`sudo` only where root is needed**, and always through `CBS_SUDO` (the
  runners do that). `cbs-check` never uses it; `chromebrew --install` must
  refuse to run as root.
- **Ask first.** Anything that changes the device, deletes something or
  cannot be undone goes behind `confirm "..."`. `--yes` answers it, no
  terminal without `--yes` refuses it; never add another way around it.
- **ChromeOS only, unless it only reads.** Call `require_chromeos` at the
  top of a command that changes the device. Read-only commands and reports
  run anywhere and degrade to `unknown` (see `lib/core/chromeos.sh`).
- **Every path through `CBS_*`.** Use `$CBS_STATEFUL`, `$CBS_USER_HOME`,
  `$CBS_VBOOT_BIN`, `$CBS_HOME`, `$CBS_CREW_PREFIX`, `$CBS_PROC_MOUNTS`, ...
  from `lib/core/chromeos.sh` and `crew.sh`, never a literal `/mnt/...`, so
  that the tests can point everything at a sandbox.
- **Downloads** go through `download` (https only; `file://` only with the
  test hook `CHROMEBREW_SCRIPTS_ALLOW_FILE_SOURCE=1`) and are checked with
  `verify_sha256` when the source publishes a checksum. Nothing is run from
  a download without a reason you can name in the docs (the Chromebrew
  installer is that one exception, and it says so).
- **Only documented methods.** A reset, remount or repair method goes in
  only when ChromeOS or Chromebrew documents it; link the documentation in
  the module's header comment and in `docs/<name>.md`, and say in the page's
  "Not verified here" section what the tests cannot check.
- **Settings** are keys in `CBS_CFG_DEFAULT` and `CBS_CFG_TYPE` in
  `lib/core/config.sh` (bool, int, url, color, name or path); a new one also
  goes into `config.example` and the README's table, and gets a 2.0.0 alias
  in `CBS_CFG_ALIAS` only if it replaces an old variable.
- **Messages** say what happened and what to do next, in one line, without
  trailing punctuation; `step_fail` notes name the command and the exit code
  (`rc_note`). Warnings and errors always reach the console, even with
  `--quiet`.
- **Style.** Two-space indent, `local` for every variable, quote everything,
  `shellcheck` clean (`tests/lint.sh`), and a header comment that says what
  the module is for and anything surprising about it.

### 4. The single-file build

`build.sh` copies `bin/chromebrew-scripts` and replaces the block between its
`# @@BUNDLE-MODULES-BEGIN@@` and `# @@BUNDLE-MODULES-END@@` markers with the
modules it sources, in that order, under `# ==== lib/... ====` banners; sets
`CBS_BUNDLED=1`, records `CBS_BUNDLE_VERSION` and `CBS_BUNDLE_COMMIT`, and
embeds the completion script. Anything a module does at load time therefore
also happens in the single file, in the same order, and anything that reads
a file relative to `lib/` must not: the single file has no `lib/`. The test
suite runs every test against both (`tests/run.sh`), and `tests/lint.sh`
shellchecks the build. `dist/` is ignored by git and never edited by hand.

## Writing tests

Tests live in `tests/unit/<name>.bats` and `load ../test_helper`. Call
`setup_sandbox` in `setup`; it gives you:

- `$SANDBOX`, a fake root with `etc/`, `mnt/stateful_partition`,
  `usr/local`, `usr/share/vboot/bin`, `home/chronos/user` and `proc/`;
  `CBS_ROOT` points at it, `CBS_HOME` at a scratch home,
  `CBS_SYSTEM_CONFIG` at a file under the sandbox. `CBS_ASSUME_CHROMEOS=1`
  and `NO_COLOR=1` are set; `unset CBS_ASSUME_CHROMEOS` and call
  `write_lsb_release [NAME] [TRACK] [VERSION]` to test detection,
  `write_cmdline verified|plain` and `write_mounts ROOT_OPTS STATEFUL_OPTS
  HOME_OPTS` for the probes, `use_crossystem_stub` with
  `STUB_CROSSYSTEM_<flag>=N` for `crossystem`.
- `$CBS_BIN_DIR`, the commands under test: `bin/` or, with
  `CBS_TEST_TARGET=bundle`, a fresh single-file build with its symlinks. Run
  the program as `"$CBS_BIN_DIR/rw" -ny`, never as `bin/rw`, so the test
  covers both builds.
- `tests/stubs` first on `PATH`: `sudo` (logs, then runs the command),
  `crew` (`version`, `list installed` from `STUB_CREW_INSTALLED`, `install`
  failing for names in `STUB_CREW_INSTALL_FAIL`), `curl` (copies `file://`
  URLs, serves a tarball of the checkout for `*.tar.gz`, writes a fake
  installer otherwise), `mount`, `reboot`, `crossystem`, and
  `make_dev_ssd.sh` copied into the sandbox's vboot directory. Each appends
  `name args` to `$STUB_LOG`; `STUB_EXIT_<name>=N` (`STUB_EXIT_sudo=1`,
  `STUB_EXIT_make_dev_ssd_sh=3`) makes one fail. `without_crew` takes `crew`
  off the `PATH`.
- Assertions: `assert_called`, `assert_not_called`, `calls`,
  `assert_output_contains`, `assert_output_not_contains`, `assert_contains`,
  `assert_equal`, `log_files` (the run logs written so far),
  `assert_version_output`.
- `run_as_user CMD...` runs a command as uid 65534 when the suite runs as
  root (and as you otherwise), for `chromebrew --install`, which refuses
  root; `EXPECT_UID` is the uid it ran as.
- `load_cbs` sources the core modules into the test for unit-testing a
  function (`config_parse_file`, `args_parse`, ...). It defines the toolkit's
  own `run`, so use `run_fn FUNC ARGS...` instead of bats' `run` afterwards.
- `make_upstream DIR`, `bump_upstream DIR VERSION`, `make_release DIR BUNDLE
  VERSION` and `tgit` build the local git repositories and fake releases the
  self-update tests use; `build_bundle DIR` makes a single-file build with
  its symlinks.

Cover at least: `--help`, every option, the confirmation refusal without
`--yes` on a non-terminal stdin, `--dry-run` leaving the sandbox untouched
and calling no stub but the read-only ones, the real run's calls (through
`assert_called`), the failure path (the command must not continue after a
failed step, and must exit 1), and that the run log holds what the terminal
showed. Run one file with `CBS_TEST_TARGET=modular bats tests/unit/<name>.bats`
while you work, and `tests/run.sh` before you push.

A new external program needs a stub: add a symlink to `tests/stubs/stub.sh`
(the generic logger, which honours `STUB_EXIT_<name>`) or a small script, and
list a script in `tests/lint.sh`.

## Pull requests

- One command, fix or probe per pull request is easiest to review.
- Say which ChromeOS release and channel you ran it on, and paste the output
  of `cbs-check` and of the command with `--dry-run` and, if you ran it,
  for real (the run log has it all).
- Don't bump `VERSION`; that happens when a release is tagged (see the
  README's [Development](README.md#development)).
