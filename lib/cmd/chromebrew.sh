#!/usr/bin/env bash
# lib/cmd/chromebrew.sh - install, remove, update or inspect Chromebrew, and
# back up / restore its package list.
# References:
#   https://github.com/chromebrew/chromebrew
#   https://github.com/chromebrew/chromebrew/wiki/How-to-remove-chromebrew
#   https://raw.githubusercontent.com/chromebrew/chromebrew/master/install.sh

CBS_CB_ACTION=""
CBS_CB_FILE=""
CBS_CB_INSTALLER=""

cmd_chromebrew_usage() {
  cat <<EOF
Usage: chromebrew ACTION [options]

Actions (exactly one):
  -i, --install           download the Chromebrew installer and run it
                          (yes | bash install.sh) after the pre-flight checks
  -r, --remove            uninstall Chromebrew: clears $CBS_CREW_PREFIX/*
                          (everything under the prefix except this toolkit)
                          and strips the Chromebrew lines from
                          $CBS_HOME/.bashrc after backing it up
  -u, --update            crew update, then yes | crew upgrade
  -s, --status            is crew installed? version, prefix, ChromeOS detected?
  -b, --backup [FILE]     save the installed package list (plus crew version
                          and date) to FILE (default: a new file in
                          BACKUP_DIR, ~/MyFiles/Downloads or ~/Downloads)
      --restore FILE      install every package listed in FILE that is not
                          installed yet (yes | crew install NAME, one by one)

Options:
  -f, --force             install anyway when a pre-flight check fails
                          (unsupported channel, Crostini, low free space);
                          also sets CREW_FORCE_INSTALL=1 for the installer,
                          which then installs the build tools too

Pre-flight checks before --install: not root, curl present, not inside a
Crostini container, release channel stable or ltc (the installer rejects
beta, dev and canary), at least MIN_FREE_MB (default 1024) free on
$CBS_STATEFUL.

Settings (config file or environment): CREW_INSTALLER_URL, CREW_TIMEOUT
(seconds per crew command, default 3600), CREW_PREFIX (default /usr/local),
MIN_FREE_MB, BACKUP_DIR, FORCE_INSTALL.

EOF
  args_common_usage
}

cmd_chromebrew_options() {
  printf '%s\n' --install --remove --update --status --backup --restore --force
}

cmd_chromebrew_parse() {
  local action=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -i|--install) action="${action:+$action }install" ;;
      -r|--remove) action="${action:+$action }remove" ;;
      -u|--update) action="${action:+$action }update" ;;
      -s|--status) action="${action:+$action }status" ;;
      -b|--backup)
        action="${action:+$action }backup"
        if [ $# -ge 2 ] && [[ "$2" != -* ]]; then CBS_CB_FILE="$2"; shift; fi ;;
      --restore)
        action="${action:+$action }restore"
        if [ $# -ge 2 ] && [[ "$2" != -* ]]; then CBS_CB_FILE="$2"; shift; else
          log_error "--restore needs the file to restore from"; return 2
        fi ;;
      -f|--force) config_set FORCE_INSTALL 1 flag ;;
      *) log_error "unknown option: $1"; return 2 ;;
    esac
    shift
  done
  case "$action" in
    '')
      log_error "choose an action: chromebrew -i | --install | -r | --remove | -u | --update | -s | --status | -b | --backup [FILE] | --restore FILE"
      return 2 ;;
    *' '*)
      log_error "choose exactly one action (got: $action)"
      return 2 ;;
  esac
  CBS_CB_ACTION="$action"
  [ -n "$CBS_CB_FILE" ] && [[ "$CBS_CB_FILE" != /* ]] && CBS_CB_FILE="$PWD/$CBS_CB_FILE"
  return 0
}

# ---------------------------------------------------------------- install --
# cb_step_prechecks: refuse what the Chromebrew installer would refuse, or
# what is known to go wrong, before anything is downloaded.
cb_step_prechecks() {
  local problems=() warnings=() mb min
  if crew_bin >/dev/null; then
    step_fail "chromebrew is currently installed ($(crew_bin)); use --update, or --remove first"
    return 1
  fi
  if is_root; then
    step_fail "Chromebrew must not be installed as root; run 'chromebrew --install' as the chronos user"
    return 1
  fi
  if ! has_cmd curl; then
    step_fail "curl is required to download the Chromebrew installer"
    return 1
  fi
  if is_crostini; then
    problems+=("this is a Crostini container ($CBS_CROSTINI_DIR exists); the Chromebrew installer does not support it")
  fi
  if is_chromeos; then
    case "$(chromeos_channel)" in
      unknown) warnings+=("the release channel could not be read from $CBS_LSB_RELEASE") ;;
      stable|ltc|lts) ;;
      *) problems+=("the $(chromeos_channel) channel is not supported by the Chromebrew installer (stable and ltc are)") ;;
    esac
  fi
  min=$(cfg MIN_FREE_MB)
  if mb=$(free_space_mb "$CBS_STATEFUL"); then
    if [ "$mb" -lt "$min" ]; then
      problems+=("only $(human_mb "$mb") free on $CBS_STATEFUL (MIN_FREE_MB=$min)")
    fi
  else
    warnings+=("free space on $CBS_STATEFUL could not be determined")
    mb=""
  fi
  local w
  for w in "${warnings[@]-}"; do [ -n "$w" ] && log_warn "$w"; done
  if [ ${#problems[@]} -gt 0 ]; then
    for w in "${problems[@]}"; do log_error "$w"; done
    if cfg_bool FORCE_INSTALL; then
      log_warn "continuing anyway (--force / CREW_FORCE_INSTALL=1); the installer is told the same and will also install the build tools"
      step_warn "${#problems[@]} check(s) overridden by --force"
      return 0
    fi
    step_fail "${#problems[@]} check(s) failed; pass --force (or set CREW_FORCE_INSTALL=1) to install anyway"
    return 1
  fi
  step_ok "channel $(chromeos_channel)${mb:+, $(human_mb "$mb") free on $CBS_STATEFUL}"
}

cb_step_download() {
  local url tmp
  url=$(cfg CREW_INSTALLER_URL)
  if [ "$CBS_DRY_RUN" = 1 ]; then
    log_dry "would download $url"
    step_dry "would download the installer"
    return 0
  fi
  tmp=$(tmp_dir) || { step_fail "cannot create a temporary directory"; return 1; }
  CBS_CB_INSTALLER="$tmp/install.sh"
  if ! download "$url" "$CBS_CB_INSTALLER"; then
    step_fail "could not download the Chromebrew installer from $url"
    return 1
  fi
  step_ok "downloaded $url"
}

cb_step_run_installer() {
  local -a to env=()
  local rc=0
  # shellcheck disable=SC2207  # the prefix is "timeout -k 10 N" or empty
  to=($(crew_timeout_prefix))
  cfg_bool FORCE_INSTALL && env=(env CREW_FORCE_INSTALL=1)
  if [ "$CBS_DRY_RUN" = 1 ]; then
    log_dry "would run: yes | $(cbs_quote ${env[@]+"${env[@]}"} ${to[@]+"${to[@]}"} bash install.sh)"
    step_dry "would run the installer, answering yes to its prompts"
    return 0
  fi
  log_info "running the Chromebrew installer (answering yes to its prompts)"
  do_pipe "yes | $(cbs_quote ${env[@]+"${env[@]}"} ${to[@]+"${to[@]}"} bash "$CBS_CB_INSTALLER")" \
    yes_pipe ${env[@]+"${env[@]}"} ${to[@]+"${to[@]}"} bash "$CBS_CB_INSTALLER" || rc=$?
  if [ "$rc" -ne 0 ]; then
    step_fail "the Chromebrew installer failed ($(rc_note "$rc"))"
    return 1
  fi
  step_updated "Chromebrew installed; run: source $CBS_HOME/.bashrc"
}

cb_install() {
  run_step "pre-flight checks" cb_step_prechecks || return 1
  run_step "download the Chromebrew installer" cb_step_download || return 1
  run_step "run the Chromebrew installer" cb_step_run_installer || return 1
}

# ----------------------------------------------------------------- update --
cb_step_crew_update() {
  local -a to
  local rc=0
  # shellcheck disable=SC2207
  to=($(crew_timeout_prefix))
  if ! crew_bin >/dev/null; then
    step_fail "chromebrew is not installed; to install it run 'chromebrew --install'"
    return 1
  fi
  CBS_RUN_TIMEOUT=0 do_run ${to[@]+"${to[@]}"} crew update || rc=$?
  if [ "$rc" -ne 0 ]; then
    step_fail "crew update failed ($(rc_note "$rc"))"
    return 1
  fi
  [ "$CBS_DRY_RUN" = 1 ] && step_dry "would run crew update"
  return 0
}

cb_step_crew_upgrade() {
  local -a to
  local rc=0
  # shellcheck disable=SC2207
  to=($(crew_timeout_prefix))
  do_pipe "yes | $(cbs_quote ${to[@]+"${to[@]}"} crew upgrade)" yes_pipe ${to[@]+"${to[@]}"} crew upgrade || rc=$?
  if [ "$rc" -ne 0 ]; then
    step_fail "crew upgrade failed ($(rc_note "$rc"))"
    return 1
  fi
  if [ "$CBS_DRY_RUN" = 1 ]; then step_dry "would run yes | crew upgrade"; else step_updated "packages upgraded"; fi
}

cb_update() {
  run_step "crew update" cb_step_crew_update || return 1
  run_step "crew upgrade" cb_step_crew_upgrade || return 1
}

# ----------------------------------------------------------------- remove --
# _cb_toolkit_path: the file or directory that is this toolkit.
_cb_toolkit_path() {
  if [ "$CBS_BUNDLED" = 1 ]; then printf '%s\n' "$CBS_BIN"; else printf '%s\n' "$CBS_ROOT_DIR"; fi
}

# _cb_is_toolkit_path PATH: PATH (symlinks resolved) is this toolkit or inside it
_cb_is_toolkit_path() {
  local real toolkit
  toolkit=$(_cb_toolkit_path)
  real=$(readlink -f -- "$1" 2>/dev/null) || return 1
  [ "$real" = "$toolkit" ] || [[ "$real" == "$toolkit"/* ]]
}

# _cb_shelters_toolkit DIR: DIR is a real directory holding toolkit paths
_cb_shelters_toolkit() {
  local dir="$1" real child toolkit
  toolkit=$(_cb_toolkit_path)
  [ -d "$dir" ] && [ ! -L "$dir" ] || return 1
  real=$(cd -P "$dir" && pwd)
  [[ "$toolkit" == "$real"/* ]] && return 0
  for child in "$dir"/*; do
    [ -e "$child" ] || [ -L "$child" ] || continue
    _cb_is_toolkit_path "$child" && return 0
  done
  return 1
}

# _cb_clear_dir DIR: remove DIR/* except this toolkit and symlinks into it
_cb_clear_dir() {
  local entry rc=0
  for entry in "$1"/*; do
    [ -e "$entry" ] || [ -L "$entry" ] || continue
    if _cb_is_toolkit_path "$entry"; then
      log_info "keeping $entry"
    elif _cb_shelters_toolkit "$entry"; then
      _cb_clear_dir "$entry" || rc=1
    else
      do_sudo rm -rf "$entry" || rc=1
    fi
  done
  return "$rc"
}

cb_step_bashrc() {
  local rc="$CBS_HOME/.bashrc" backup
  if [ ! -f "$rc" ]; then
    step_skip "no $rc"
    return 0
  fi
  backup="$rc.chromebrew-scripts.$(printf '%(%Y%m%d-%H%M%S)T' -1).bak"
  if ! do_run cp -p "$rc" "$backup"; then
    step_fail "could not back up $rc; leaving it untouched"
    return 1
  fi
  if ! do_run sed -i -e '/source.*profile/d' -e '/# DO NOT DELETE THIS LINE/d' \
      -e '/# See .*profile for further details/d' "$rc"; then
    step_fail "could not edit $rc; the backup is at $backup"
    return 1
  fi
  if [ "$CBS_DRY_RUN" = 1 ]; then
    step_dry "would back up $rc and strip the Chromebrew lines"
  else
    step_updated "Chromebrew lines removed; backup at $backup"
  fi
}

cb_step_clear_prefix() {
  if ! _cb_clear_dir "$CBS_CREW_PREFIX"; then
    step_fail "some entries under $CBS_CREW_PREFIX could not be removed"
    return 1
  fi
  if [ "$CBS_DRY_RUN" = 1 ]; then
    step_dry "would clear $CBS_CREW_PREFIX/* (keeping $(_cb_toolkit_path))"
  else
    step_updated "$CBS_CREW_PREFIX/* cleared (kept $(_cb_toolkit_path))"
  fi
}

cb_remove() {
  local real_prefix
  if ! crew_bin >/dev/null; then
    log_warn "crew was not found; clearing whatever is left under $CBS_CREW_PREFIX anyway"
  fi
  real_prefix=$(readlink -f -- "$CBS_CREW_PREFIX" 2>/dev/null) || real_prefix=''
  case "$real_prefix" in
    ''|/|/home|/home/*|/mnt|/mnt/stateful_partition|/usr|/etc|/root|/opt|/var|/bin|/sbin|/lib|/lib64)
      log_error "refusing to clear '$CBS_CREW_PREFIX': not a safe Chromebrew prefix"
      return 1 ;;
  esac
  if [[ "$CBS_CREW_PREFIX" != /* ]] || [ ! -d "$CBS_CREW_PREFIX" ]; then
    log_error "refusing to clear '$CBS_CREW_PREFIX': not an existing absolute directory"
    return 1
  fi
  confirm "Are you sure you want to uninstall Chromebrew? This clears $CBS_CREW_PREFIX/*" || return 1
  run_step "strip the Chromebrew lines from $CBS_HOME/.bashrc" cb_step_bashrc || return 1
  run_step "clear $CBS_CREW_PREFIX" cb_step_clear_prefix || return 1
  [ "$CBS_DRY_RUN" = 1 ] || log_info "Chromebrew removed; open a new shell to pick up the changed $CBS_HOME/.bashrc"
  return 0
}

# ----------------------------------------------------------------- status --
cb_status() {
  local crew
  log_kv "chromebrew-scripts" "$(version_string) at $(_cb_toolkit_path)"
  log_kv "ChromeOS detected" "$(is_chromeos && printf 'yes: %s' "$(chromeos_describe)" || printf 'no')"
  log_kv "Chromebrew prefix" "$CBS_CREW_PREFIX"
  if crew=$(crew_bin); then
    log_kv "crew" "$crew"
    log_kv "crew version" "$(crew_version)"
  else
    log_kv "crew" "not installed"
  fi
  return 0
}

# ----------------------------------------------------------------- backup --
# cb_backup_dir: BACKUP_DIR, else the Downloads folder (visible in the Files
# app, easy to copy to Drive or USB), else the toolkit's config directory.
cb_backup_dir() {
  local d
  d=$(cfg BACKUP_DIR)
  if [ -n "$d" ]; then printf '%s\n' "$d"; return 0; fi
  for d in "$CBS_HOME/MyFiles/Downloads" "$CBS_HOME/Downloads"; do
    if [ -d "$d" ]; then printf '%s\n' "$d"; return 0; fi
  done
  printf '%s/chromebrew-scripts/backups\n' "${XDG_CONFIG_HOME:-$CBS_HOME/.config}"
}

cb_step_backup() {
  local crew file pkgs n
  if ! crew=$(crew_bin); then
    step_fail "chromebrew is not installed; nothing to back up"
    return 1
  fi
  file="${CBS_CB_FILE:-$(cb_backup_dir)/chromebrew-packages-$(printf '%(%Y%m%d-%H%M%S)T' -1).txt}"
  pkgs=$(crew_installed) || { step_fail "crew list installed failed"; return 1; }
  n=0
  [ -n "$pkgs" ] && n=$(printf '%s\n' "$pkgs" | grep -c .)
  if [ "$n" -eq 0 ]; then
    log_warn "crew reports no installed packages (is this Chromebrew healthy?); writing an empty list"
  fi
  if [ "$CBS_DRY_RUN" = 1 ]; then
    log_dry "would write $n package name(s) to $file"
    step_dry "$n package(s) -> $file"
    return 0
  fi
  if ! mkdir -p -- "$(dirname "$file")" 2>/dev/null; then
    step_fail "cannot create $(dirname "$file")"
    return 1
  fi
  {
    printf '# chromebrew-scripts package list (%s)\n' "$(version_string)"
    printf '# saved    %(%Y-%m-%d %H:%M:%S %z)T\n' -1
    printf '# crew     %s (%s)\n' "$(crew_version)" "$crew"
    printf '# os       %s\n' "$(chromeos_describe)"
    printf '# restore  chromebrew --restore %s\n' "$file"
    [ -n "$pkgs" ] && printf '%s\n' "$pkgs"
  } > "$file" || { step_fail "cannot write $file"; return 1; }
  step_updated "$n package(s) saved to $file"
  log_info "a powerwash erases every local file: copy $file to Google Drive, a USB stick or another machine"
}

# cb_read_list FILE: the package names in a backup file, one per line.
cb_read_list() {
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [ -z "$line" ] && continue
    if [[ "$line" =~ ^[A-Za-z0-9][A-Za-z0-9_.+-]*$ ]]; then
      printf '%s\n' "$line"
    else
      log_warn "ignoring a line that is not a package name: $line"
    fi
  done < "$1"
}

cb_step_restore() {
  local crew file installed p
  local -a wanted=() todo=() failed=() to
  local skipped=0 done_count=0 rc
  file="$CBS_CB_FILE"
  if [ ! -r "$file" ]; then
    step_fail "cannot read $file"
    return 1
  fi
  if ! crew=$(crew_bin); then
    step_fail "chromebrew is not installed; run 'chromebrew --install' first, then restore"
    return 1
  fi
  mapfile -t wanted < <(cb_read_list "$file")
  if [ ${#wanted[@]} -eq 0 ]; then
    step_skip "$file lists no packages"
    return 0
  fi
  installed=$(crew_installed) || installed=""
  for p in "${wanted[@]}"; do
    if grep -qx -- "$p" <<< "$installed"; then
      skipped=$((skipped + 1))
    else
      todo+=("$p")
    fi
  done
  log_info "${#wanted[@]} package(s) listed, $skipped already installed, ${#todo[@]} to install"
  if [ ${#todo[@]} -eq 0 ]; then
    step_ok "every package in $file is already installed"
    return 0
  fi
  # shellcheck disable=SC2207
  to=($(crew_timeout_prefix))
  if [ "$CBS_DRY_RUN" = 1 ]; then
    for p in "${todo[@]}"; do
      log_dry "would run: yes | $(cbs_quote ${to[@]+"${to[@]}"} crew install "$p")"
    done
    step_dry "would install ${#todo[@]} package(s); $skipped already installed"
    return 0
  fi
  for p in "${todo[@]}"; do
    log_info "installing $p"
    rc=0
    do_pipe "yes | $(cbs_quote ${to[@]+"${to[@]}"} crew install "$p")" yes_pipe ${to[@]+"${to[@]}"} "$crew" install "$p" || rc=$?
    if [ "$rc" -eq 0 ]; then
      done_count=$((done_count + 1))
    else
      log_error "$p: crew install failed ($(rc_note "$rc"))"
      failed+=("$p")
    fi
  done
  if [ ${#failed[@]} -gt 0 ]; then
    step_fail "${#failed[@]} failed: ${failed[*]} ($done_count installed, $skipped already installed)"
    return 1
  fi
  step_updated "$done_count installed, $skipped already installed"
}

cmd_chromebrew_run() {
  case "$CBS_CB_ACTION" in
    install|remove|update) require_chromeos || return 1 ;;
  esac
  case "$CBS_CB_ACTION" in
    install) cb_install ;;
    remove) cb_remove ;;
    update) cb_update ;;
    status) cb_status ;;
    backup) run_step "back up the Chromebrew package list" cb_step_backup ;;
    restore) run_step "restore the Chromebrew package list" cb_step_restore ;;
    *) log_error "no action"; return 2 ;;
  esac
}
