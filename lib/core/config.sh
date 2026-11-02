#!/usr/bin/env bash
# lib/core/config.sh - settings from config files, environment and flags.
#
# Precedence (lowest to highest):
#   built-in default < /etc/chromebrew-scripts.conf < user config < environment < flags
#
# Config files are simple KEY=value lines. They are parsed line by line and
# never sourced or eval'd, so a hostile value cannot run code. Unknown keys
# and malformed values are reported and ignored. See config.example.

CBS_DEFAULT_REPO="https://github.com/uberhacker/chromebrew-scripts"

# Allowed keys with their default values and a validation class.
#   bool     1/0/yes/no/true/false/on/off
#   int      non-negative integer
#   url      https:// URL (file:// only when CHROMEBREW_SCRIPTS_ALLOW_FILE_SOURCE=1)
#   color    auto|always|never
#   name     a git ref name
#   path     an absolute path (no "..", no spaces or shell metacharacters)
declare -gA CBS_CFG_DEFAULT=(
  [SELF_UPDATE_REPO]="$CBS_DEFAULT_REPO"
  [SELF_UPDATE_BRANCH]=""
  [TIMEOUT]="300"
  [CREW_TIMEOUT]="3600"
  [DOWNLOAD_TIMEOUT]="300"
  [CREW_INSTALLER_URL]="https://raw.githubusercontent.com/chromebrew/chromebrew/master/install.sh"
  [CREW_PREFIX]=""
  [FORCE_INSTALL]="0"
  [MIN_FREE_MB]="1024"
  [BACKUP_DIR]=""
  [COLOR]="auto"
  [LOGGING]="1"
  [LOG_DIR]=""
  [LOG_KEEP]="20"
)
declare -gA CBS_CFG_TYPE=(
  [SELF_UPDATE_REPO]=url
  [SELF_UPDATE_BRANCH]=name
  [TIMEOUT]=int
  [CREW_TIMEOUT]=int
  [DOWNLOAD_TIMEOUT]=int
  [CREW_INSTALLER_URL]=url
  [CREW_PREFIX]=path
  [FORCE_INSTALL]=bool
  [MIN_FREE_MB]=int
  [BACKUP_DIR]=path
  [COLOR]=color
  [LOGGING]=bool
  [LOG_DIR]=path
  [LOG_KEEP]=int
)
# Older names (2.0.0) still accepted from the environment, lowest priority.
declare -gA CBS_CFG_ALIAS=(
  [CBS_CREW_INSTALLER_URL]=CREW_INSTALLER_URL
  [CBS_CREW_TIMEOUT]=CREW_TIMEOUT
  [CBS_CURL_TIMEOUT]=DOWNLOAD_TIMEOUT
  [CBS_PREFIX]=CREW_PREFIX
  [CREW_FORCE_INSTALL]=FORCE_INSTALL
  [CBS_REF]=SELF_UPDATE_BRANCH
)
declare -gA CBS_CFG=()        # effective values
declare -gA CBS_CFG_SOURCE=() # where each value came from (for --list and the log)

config_user_file() {
  printf '%s/chromebrew-scripts/config\n' "${XDG_CONFIG_HOME:-${CBS_HOME:-$HOME}/.config}"
}

config_system_file() {
  printf '%s\n' "${CBS_SYSTEM_CONFIG:-${CBS_ROOT:-}/etc/chromebrew-scripts.conf}"
}

# config_valid TYPE VALUE: validation per class.
config_valid() {
  local type="$1" value="$2"
  # No control characters anywhere.
  [[ "$value" =~ [[:cntrl:]] ]] && return 1
  case "$type" in
    bool) [[ "${value,,}" =~ ^(1|0|yes|no|true|false|on|off|y|n)$ ]] ;;
    int) [[ "$value" =~ ^[0-9]{1,9}$ ]] ;;
    url)
      if [[ "$value" =~ ^https://[A-Za-z0-9._~:/?#@!$\&\'()*+,\;=%-]+$ ]]; then
        return 0
      fi
      if [ "${CHROMEBREW_SCRIPTS_ALLOW_FILE_SOURCE:-0}" = 1 ] && [[ "$value" =~ ^file:///[A-Za-z0-9._/-]+$ ]]; then
        return 0
      fi
      return 1 ;;
    color) [[ "$value" =~ ^(auto|always|never)$ ]] ;;
    name) [[ "$value" =~ ^[A-Za-z0-9_./-]*$ ]] && [[ "$value" != *..* ]] && [[ "$value" != -* ]] ;;
    path) [ -z "$value" ] || { [[ "$value" =~ ^/[A-Za-z0-9_.@+/-]*$ ]] && [[ "$value" != *..* ]]; } ;;
    *) return 1 ;;
  esac
}

# config_normalize TYPE VALUE: canonical form (bools become 1/0).
config_normalize() {
  local type="$1" value="$2"
  case "$type" in
    bool) if bool "$value"; then echo 1; else echo 0; fi ;;
    url) printf '%s\n' "${value%/}" ;;
    *) printf '%s\n' "$value" ;;
  esac
}

# config_set KEY VALUE SOURCE: validate and store.
config_set() {
  local key="$1" value="$2" src="$3" type
  type="${CBS_CFG_TYPE[$key]:-}"
  if [ -z "$type" ]; then
    log_warn "config: unknown key '$key' ($src) ignored"
    return 1
  fi
  if ! config_valid "$type" "$value"; then
    log_warn "config: invalid value for $key ($src) ignored"
    return 1
  fi
  CBS_CFG[$key]=$(config_normalize "$type" "$value")
  CBS_CFG_SOURCE[$key]="$src"
  return 0
}

# config_parse_file FILE: read KEY=value lines.
config_parse_file() {
  local file="$1" line key value lineno=0
  [ -r "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    # Trim surrounding whitespace.
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [ -z "$line" ] && continue
    [[ "$line" == \#* ]] && continue
    if ! [[ "$line" =~ ^([A-Z][A-Z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
      log_warn "config: $file:$lineno: not a KEY=value line, ignored"
      continue
    fi
    key="${BASH_REMATCH[1]}"
    value="${BASH_REMATCH[2]}"
    # Strip one layer of matching quotes.
    if [[ "$value" =~ ^\"(.*)\"$ ]] || [[ "$value" =~ ^\'(.*)\'$ ]]; then
      value="${BASH_REMATCH[1]}"
    fi
    config_set "$key" "$value" "$file:$lineno" || true
  done < "$file"
}

# config_load: defaults, system file, user file (or --config FILE),
# environment (older CBS_* names included), in that order.
config_load() {
  local key alias
  for key in "${!CBS_CFG_DEFAULT[@]}"; do
    CBS_CFG[$key]="${CBS_CFG_DEFAULT[$key]}"
    CBS_CFG_SOURCE[$key]="default"
  done
  config_parse_file "$(config_system_file)"
  if [ -n "${CBS_CONFIG_FILE:-}" ]; then
    if [ -r "$CBS_CONFIG_FILE" ]; then
      config_parse_file "$CBS_CONFIG_FILE"
    else
      log_warn "config file not readable: $CBS_CONFIG_FILE"
    fi
  else
    config_parse_file "$(config_user_file)"
  fi
  # Older environment names first, so that the current names win.
  for alias in "${!CBS_CFG_ALIAS[@]}"; do
    key="${CBS_CFG_ALIAS[$alias]}"
    if config_in_env "$alias" && ! config_in_env "$key"; then
      config_set "$key" "${!alias}" "env $alias" || true
    fi
  done
  # CBS_REPO=owner/name (install.sh 2.0.0) names a GitHub repository.
  if config_in_env CBS_REPO && ! config_in_env SELF_UPDATE_REPO; then
    if [[ "$CBS_REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
      config_set SELF_UPDATE_REPO "https://github.com/$CBS_REPO" "env CBS_REPO" || true
    else
      config_set SELF_UPDATE_REPO "$CBS_REPO" "env CBS_REPO" || true
    fi
  fi
  for key in "${!CBS_CFG_DEFAULT[@]}"; do
    if config_in_env "$key"; then
      config_set "$key" "${!key}" "env" || true
    fi
  done
}

# config_in_env NAME: NAME came from the environment (exported) and is not
# empty. The toolkit's own defaults (CBS_CREW_TIMEOUT, ...) are plain shell
# variables and do not count.
config_in_env() {
  local d
  d=$(declare -p "$1" 2>/dev/null) || return 1
  [[ "$d" == "declare -x"* ]] && [ -n "${!1:-}" ]
}

# cfg KEY: print the effective value.
cfg() { printf '%s\n' "${CBS_CFG[$1]-}"; }

# cfg_bool KEY: true when the effective value is on.
cfg_bool() { bool "${CBS_CFG[$1]-0}"; }

# config_print_nondefault PREFIX: one "PREFIX KEY=value (source)" line per
# setting that is not at its default (for the log header and --list).
config_print_nondefault() {
  local prefix="$1" key
  for key in $(printf '%s\n' "${!CBS_CFG[@]}" | sort); do
    [ "${CBS_CFG_SOURCE[$key]}" = default ] && continue
    printf '%s%s=%s (%s)\n' "$prefix" "$key" "${CBS_CFG[$key]}" "${CBS_CFG_SOURCE[$key]}"
  done
}
