#!/usr/bin/env bash
# lib/core/args.sh - the command line options every command shares.
#
# args_parse takes the whole command line, keeps the common options in
# CBS_ARG_* and leaves everything else (the command's own options, and
# anything after "--") in CBS_CMD_ARGS for the command module to parse.
# args_apply then layers the flags on top of the config/environment values,
# so that flags always win.

CBS_ARG_DRY_RUN=""
CBS_ARG_YES=""
CBS_ARG_VERBOSE=""
CBS_ARG_QUIET=""
CBS_ARG_COLOR=""
CBS_ARG_TIMEOUT=""
CBS_ARG_LOGGING=""
CBS_ARG_SELF_UPDATE=0
CBS_ARG_SOURCE=""
CBS_ARG_BRANCH=""
CBS_ARG_VERSION=0
CBS_ARG_HELP=0
CBS_ARG_COMPLETION=""
CBS_CONFIG_FILE="${CBS_CONFIG_FILE:-}"
CBS_LOG_PATH="${CBS_LOG_PATH:-}"   # --log FILE
CBS_CMD_ARGS=()

# args_common_usage: the shared options, for every command's --help.
args_common_usage() {
  cat <<EOF
Common options (every command):
  -n, --dry-run           print what would be done; change nothing
  -y, --yes               answer the [y/N] confirmation (required without a terminal)
  -v, --verbose           show every command that is run
  -q, --quiet             hide third-party output; show only status lines
      --no-color          disable colours (NO_COLOR and non-TTY output do too)
      --color WHEN        auto (default), always or never
      --timeout SECONDS   per-command timeout (default 300; crew: CREW_TIMEOUT)
      --config FILE       read this config file instead of the user config
      --log FILE          write this run's log to FILE
      --no-log            do not write a log file for this run
      --self-update       update chromebrew-scripts itself and exit
      --source URL        source for --self-update (https only; a fork)
      --branch NAME       branch for --self-update (git checkout or tree install)
      --version           print the version and exit
  -h, --help              show this help and exit

Config: \${XDG_CONFIG_HOME:-~/.config}/chromebrew-scripts/config and
/etc/chromebrew-scripts.conf (KEY=value). Environment variables override
the files, flags override everything. See config.example.
EOF
}

# args_need OPT VALUE: fail when an option that needs a value has none.
args_need() {
  if [ -z "${2:-}" ]; then
    log_error "option $1 requires a value"
    return 1
  fi
}

# args_parse "$@": fill CBS_ARG_* and CBS_CMD_ARGS. Returns 2 on usage error.
args_parse() {
  local opt val
  CBS_CMD_ARGS=()
  while [ $# -gt 0 ]; do
    opt="$1"; val=""
    # Split --opt=value.
    case "$opt" in
      --*=*) val="${opt#*=}"; opt="${opt%%=*}"; set -- "$opt" "$val" "${@:2}" ;;
    esac
    case "$opt" in
      -n|--dry-run) CBS_ARG_DRY_RUN=1 ;;
      -y|--yes) CBS_ARG_YES=1 ;;
      -v|--verbose) CBS_ARG_VERBOSE=1 ;;
      -q|--quiet) CBS_ARG_QUIET=1 ;;
      --no-color|--no-colour) CBS_ARG_COLOR=never ;;
      --color|--colour) args_need "$opt" "${2:-}" || return 2; CBS_ARG_COLOR="$2"; shift ;;
      --timeout) args_need "$opt" "${2:-}" || return 2; CBS_ARG_TIMEOUT="$2"; shift ;;
      --config) args_need "$opt" "${2:-}" || return 2; CBS_CONFIG_FILE="$2"; shift ;;
      --log) args_need "$opt" "${2:-}" || return 2; CBS_LOG_PATH="$2"; CBS_ARG_LOGGING=1; shift ;;
      --no-log) CBS_ARG_LOGGING=0; CBS_LOG_PATH="" ;;
      --self-update) CBS_ARG_SELF_UPDATE=1 ;;
      --source) args_need "$opt" "${2:-}" || return 2; CBS_ARG_SOURCE="$2"; shift ;;
      --branch) args_need "$opt" "${2:-}" || return 2; CBS_ARG_BRANCH="$2"; shift ;;
      --version|-V) CBS_ARG_VERSION=1 ;;
      --completion) args_need "$opt" "${2:-}" || return 2; CBS_ARG_COMPLETION="$2"; shift ;;
      -h|--help) CBS_ARG_HELP=1 ;;
      --)
        # Everything after "--" belongs to the command (rootfs passes it on).
        CBS_CMD_ARGS+=("$@")
        return 0 ;;
      -[a-zA-Z][a-zA-Z]*)
        # Combined short flags like -ny: split and parse again.
        local i chars="${opt#-}" rest=()
        for ((i = 0; i < ${#chars}; i++)); do rest+=("-${chars:i:1}"); done
        shift
        set -- "${rest[@]}" "$@"
        continue ;;
      *) CBS_CMD_ARGS+=("$opt") ;;
    esac
    shift
  done
  return 0
}

# args_apply: layer flags over the loaded configuration and export the
# runtime globals used by the rest of the program.
args_apply() {
  [ -n "$CBS_ARG_TIMEOUT" ] && { config_set TIMEOUT "$CBS_ARG_TIMEOUT" flag || return 2; }
  [ -n "$CBS_ARG_COLOR" ] && { config_set COLOR "$CBS_ARG_COLOR" flag || return 2; }
  [ -n "$CBS_ARG_LOGGING" ] && config_set LOGGING "$CBS_ARG_LOGGING" flag
  [ -n "$CBS_ARG_SOURCE" ] && { config_set SELF_UPDATE_REPO "$CBS_ARG_SOURCE" flag || return 2; }
  [ -n "$CBS_ARG_BRANCH" ] && { config_set SELF_UPDATE_BRANCH "$CBS_ARG_BRANCH" flag || return 2; }

  CBS_DRY_RUN="${CBS_ARG_DRY_RUN:-${CBS_DRY_RUN:-0}}"
  CBS_YES="${CBS_ARG_YES:-${CBS_YES:-0}}"
  CBS_VERBOSE="${CBS_ARG_VERBOSE:-${CBS_VERBOSE:-0}}"
  CBS_QUIET="${CBS_ARG_QUIET:-${CBS_QUIET:-0}}"
  if [ "$CBS_VERBOSE" = 1 ] && [ "$CBS_QUIET" = 1 ]; then
    CBS_QUIET=0
  fi
  CBS_COLOR=$(cfg COLOR)
  CBS_TIMEOUT=$(cfg TIMEOUT)
  CBS_CREW_TIMEOUT=$(cfg CREW_TIMEOUT)
  CBS_DOWNLOAD_TIMEOUT=$(cfg DOWNLOAD_TIMEOUT)
  CBS_CREW_PREFIX=$(cfg CREW_PREFIX)
  [ -n "$CBS_CREW_PREFIX" ] || CBS_CREW_PREFIX="${CBS_ROOT}/usr/local"
  export CBS_DRY_RUN CBS_VERBOSE CBS_QUIET CBS_COLOR CBS_TIMEOUT CBS_CREW_TIMEOUT CBS_DOWNLOAD_TIMEOUT
  log_init
  return 0
}
