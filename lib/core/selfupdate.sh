#!/usr/bin/env bash
# lib/core/selfupdate.sh - update this toolkit from its own source.
#
# Git checkout:  follow the remote the checkout was cloned from (origin);
#                when SELF_UPDATE_REPO or --source is set, origin must match
#                it (--source re-points it). Refuse a dirty tree, fetch,
#                fast-forward only.
# Tree install:  (a plain directory with bin/ and lib/, no .git) download the
#                branch tarball over https, sanity-check it (entry point
#                present, bash -n passes) and swap the directory in with two
#                renames. Never `reset --hard`, never chown system
#                directories to the user.
# Single file:   download the latest release's `chromebrew-scripts` asset and
#                its `.sha256`, verify, check it is a single-file build, and
#                rename it over this file (never written in place: bash reads
#                a script while running it). Nothing is replaced without a
#                published checksum.
#
# Branch: SELF_UPDATE_BRANCH when set; otherwise the checkout's current branch
# if the remote has it; otherwise the remote's default branch (git ls-remote
# --symref), falling back to "master".

CBS_SELF_UPDATE_FALLBACK_BRANCH="master"

# selfupdate_norm_url URL: canonical form for comparing remotes.
selfupdate_norm_url() {
  local u="${1%/}"
  u="${u%.git}"
  u="${u#file://}"
  u="${u,,}"
  printf '%s\n' "$u"
}

# selfupdate_origin_ok URL: may a checkout's own origin be followed? Any
# authenticated transport: https, ssh (ssh:// or scp-like host:path); never
# http:// or git:// (file:// only with the test hook).
selfupdate_origin_ok() {
  case "$1" in
    https://*|ssh://*|git+ssh://*) return 0 ;;
    file:///*) [ "${CHROMEBREW_SCRIPTS_ALLOW_FILE_SOURCE:-0}" = 1 ] && return 0 ;;
    *://*) ;;
    *:*) [[ "$1" != /* ]] && return 0 ;;
  esac
  log_error "refusing to follow origin over an insecure transport: $1 (set SELF_UPDATE_REPO or pass --source)"
  return 1
}

# selfupdate_source_ok URL: https only (file:// for tests).
selfupdate_source_ok() {
  case "$1" in
    https://*) return 0 ;;
    file:///*) [ "${CHROMEBREW_SCRIPTS_ALLOW_FILE_SOURCE:-0}" = 1 ] && return 0 ;;
  esac
  log_error "self-update source must be an https:// URL: $1"
  return 1
}

# selfupdate_remote_default_branch URL: parse `git ls-remote --symref URL HEAD`.
selfupdate_remote_default_branch() {
  local url="$1" out
  has_cmd git || return 1
  out=$(timeout 60 git ls-remote --symref "$url" HEAD 2>/dev/null </dev/null) || return 1
  out=$(printf '%s\n' "$out" | sed -n 's|^ref: refs/heads/\([^[:space:]]*\)[[:space:]]*HEAD$|\1|p' | head -n1)
  [ -n "$out" ] || return 1
  printf '%s\n' "$out"
}

# selfupdate_remote_has_branch URL BRANCH
selfupdate_remote_has_branch() {
  has_cmd git || return 1
  [ -n "$(timeout 60 git ls-remote --heads "$1" "refs/heads/$2" 2>/dev/null </dev/null)" ]
}

# _su_owner PATH: owner user name.
_su_owner() { stat -c %U "$1" 2>/dev/null; }

# _su_sudo: the privilege command for a root-owned installation, or failure.
_su_sudo() {
  [ -n "$CBS_SUDO" ] && has_cmd "${CBS_SUDO%% *}"
}

# _su_as_owner PATH CMD...: run CMD as the owner of PATH.
_su_as_owner() {
  local path="$1"; shift
  local owner me
  owner=$(_su_owner "$path")
  me=$(id -un)
  if [ -z "$owner" ] || [ "$owner" = "$me" ]; then
    log_cmd "$*"
    "$@" </dev/null
  elif is_root; then
    log_cmd "(as $owner) $*"
    if has_cmd runuser; then
      runuser -u "$owner" -- "$@" </dev/null
    else
      sudo -n -u "$owner" -H -- "$@" </dev/null
    fi
  elif [ "$owner" = root ]; then
    if ! _su_sudo; then
      log_error "$path is owned by root and ${CBS_SUDO:-sudo} is not available"
      return 1
    fi
    log_cmd "$CBS_SUDO $*"
    # shellcheck disable=SC2086
    $CBS_SUDO -n "$@" </dev/null
  else
    log_error "$path is owned by $owner; run --self-update as that user"
    return 1
  fi
}

# selfupdate_git ROOT REPO BRANCH
selfupdate_git() {
  local root="$1" repo="$2" branch="$3"
  local origin current target old_rev new_rev old_ver new_ver behind
  local -a git=(_su_as_owner "$root" git -C "$root")

  origin=$("${git[@]}" remote get-url origin 2>/dev/null) || {
    log_error "cannot read the origin remote of $root"
    return 1
  }
  if [ "$(selfupdate_norm_url "$origin")" != "$(selfupdate_norm_url "$repo")" ]; then
    if [ -n "$CBS_ARG_SOURCE" ]; then
      log_info "re-pointing origin from $origin to $repo (--source)"
      if [ "$CBS_DRY_RUN" != 1 ]; then
        "${git[@]}" remote set-url origin "$repo" || return 1
      fi
    else
      log_error "checkout origin ($origin) does not match the configured source ($repo)"
      log_error "pass --source '$repo' to re-point it, or set SELF_UPDATE_REPO to match"
      return 1
    fi
  fi

  if [ -n "$("${git[@]}" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
    log_error "refusing to update: $root has local changes (commit or stash them first)"
    return 1
  fi

  old_rev=$("${git[@]}" rev-parse --short HEAD 2>/dev/null)
  old_ver=$(cat "$root/VERSION" 2>/dev/null || echo unknown)
  current=$("${git[@]}" symbolic-ref --short -q HEAD 2>/dev/null || true)

  if [ -n "$branch" ]; then
    target="$branch"
  elif [ -n "$current" ] && selfupdate_remote_has_branch "$repo" "$current"; then
    target="$current"
  else
    target=$(selfupdate_remote_default_branch "$repo") || target="$CBS_SELF_UPDATE_FALLBACK_BRANCH"
  fi
  log_info "source: $repo (branch $target)"
  log_info "installed: $old_ver ($old_rev${current:+, on $current})"

  "${git[@]}" fetch --quiet origin "$target" || { log_error "git fetch failed"; return 1; }
  behind=$("${git[@]}" rev-list --count "HEAD..FETCH_HEAD" 2>/dev/null || echo "?")

  if [ "$CBS_DRY_RUN" = 1 ]; then
    new_rev=$("${git[@]}" rev-parse --short FETCH_HEAD 2>/dev/null)
    if [ "$current" != "$target" ]; then
      # A checkout on another branch (a development branch the remote does
      # not have, or --branch) is switched, not fast-forwarded: say so.
      log_dry "would switch from ${current:-a detached HEAD} to $target at $new_rev ($behind commit(s) not on ${current:-HEAD})"
    elif [ "$behind" = 0 ]; then
      log_dry "already up to date ($old_rev)"
    else
      log_dry "would fast-forward $old_rev -> $new_rev ($behind new commit(s) on $target)"
    fi
    return 0
  fi

  if [ "$current" != "$target" ]; then
    log_info "switching from ${current:-a detached HEAD} to $target"
    "${git[@]}" checkout --quiet "$target" || { log_error "could not switch to branch $target"; return 1; }
  fi
  "${git[@]}" pull --ff-only --quiet origin "$target" || {
    log_error "fast-forward failed; the checkout has diverged from $repo ($target)"
    return 1
  }
  new_rev=$("${git[@]}" rev-parse --short HEAD 2>/dev/null)
  new_ver=$(cat "$root/VERSION" 2>/dev/null || echo unknown)
  if [ "$old_rev" = "$new_rev" ]; then
    log_ok "already up to date: $new_ver ($new_rev)"
  elif [ "$current" != "$target" ]; then
    log_updated "switched to $target: $new_ver ($new_rev), was $old_ver ($old_rev) on ${current:-a detached HEAD}"
  else
    log_updated "updated $old_ver ($old_rev) -> $new_ver ($new_rev)"
  fi
  return 0
}

# selfupdate_check_tree DIR: is DIR a plausible chromebrew-scripts tree?
selfupdate_check_tree() {
  local dir="$1" f
  [ -f "$dir/bin/chromebrew-scripts" ] || { log_error "downloaded tree has no bin/chromebrew-scripts"; return 1; }
  [ -d "$dir/lib/core" ] || { log_error "downloaded tree has no lib/core"; return 1; }
  bash -n "$dir/bin/chromebrew-scripts" || { log_error "downloaded entry point does not parse"; return 1; }
  while IFS= read -r -d '' f; do
    bash -n "$f" || { log_error "downloaded file does not parse: ${f#"$dir"/}"; return 1; }
  done < <(find "$dir/lib" -name '*.sh' -type f -print0)
  return 0
}

# selfupdate_tarball ROOT REPO BRANCH
selfupdate_tarball() {
  local root="$1" repo="$2" branch="$3"
  local url tmp tarball top old_ver new_ver parent base staging old owner

  if [ -z "$branch" ]; then
    branch=$(selfupdate_remote_default_branch "$repo") || branch="$CBS_SELF_UPDATE_FALLBACK_BRANCH"
  fi
  url="${repo%.git}/archive/refs/heads/${branch}.tar.gz"
  old_ver=$(cat "$root/VERSION" 2>/dev/null || echo unknown)
  log_info "source: $url"
  log_info "installed: $old_ver (not a git checkout)"

  tmp=$(tmp_dir) || return 1
  tarball="$tmp/source.tar.gz"
  download "$url" "$tarball" || return 1
  mkdir -p "$tmp/x"
  tar -xzf "$tarball" -C "$tmp/x" || { log_error "could not extract the downloaded tarball"; return 1; }
  top=$(find "$tmp/x" -mindepth 1 -maxdepth 1 -type d | head -n1)
  [ -n "$top" ] || { log_error "tarball is empty"; return 1; }
  selfupdate_check_tree "$top" || return 1
  new_ver=$(cat "$top/VERSION" 2>/dev/null || echo unknown)

  if [ "$CBS_DRY_RUN" = 1 ]; then
    log_dry "would replace $root ($old_ver) with $new_ver from $branch"
    return 0
  fi

  parent=$(dirname "$root"); base=$(basename "$root")
  staging="$parent/.$base.new.$$"
  old="$parent/.$base.old.$$"
  owner=$(_su_owner "$root")
  _su_as_owner "$root" cp -a "$top" "$staging" || return 1
  if is_root && [ -n "$owner" ] && [ "$owner" != root ]; then
    chown -R "$owner" "$staging" 2>/dev/null || true
  fi
  if ! _su_as_owner "$root" mv "$root" "$old"; then
    _su_as_owner "$root" rm -rf "$staging"
    return 1
  fi
  if ! _su_as_owner "$old" mv "$staging" "$root"; then
    log_error "swap failed; restoring the previous installation"
    _su_as_owner "$old" mv "$old" "$root"
    return 1
  fi
  _su_as_owner "$root" rm -rf "$old"
  log_updated "updated $old_ver -> $new_ver ($branch)"
  return 0
}

# selfupdate_bundle FILE REPO: replace a single-file build with the newest
# release asset. Releases are built by .github/workflows/release.yml. The
# published .sha256 is fetched first and compared with this file: nothing
# else is downloaded when they match. The asset is then verified against
# that checksum, checked to parse and to be a single-file build, and
# renamed over FILE.
selfupdate_bundle() {
  local self="$1" repo="${2%.git}" url tmp sum mine new_commit new_ver dir staged
  url="$repo/releases/latest/download/chromebrew-scripts"
  [ -n "$(cfg SELF_UPDATE_BRANCH)" ] && log_warn "SELF_UPDATE_BRANCH/--branch is ignored for a single-file build (it follows releases)"
  log_info "source: $url"
  log_info "installed: $(version_string)"

  tmp=$(tmp_dir) || return 1
  if ! download "$url.sha256" "$tmp/chromebrew-scripts.sha256"; then
    log_error "no chromebrew-scripts.sha256 is published with the latest release; refusing an unverified update"
    return 1
  fi
  sum=$(head -n1 "$tmp/chromebrew-scripts.sha256"); sum="${sum%%[[:space:]]*}"; sum="${sum,,}"
  [[ "$sum" =~ ^[0-9a-f]{64}$ ]] || { log_error "the published chromebrew-scripts.sha256 does not contain a sha256"; return 1; }
  mine=$(sha256_of "$self") || { log_error "no sha256 tool available"; return 1; }
  if [ "$mine" = "$sum" ]; then
    log_ok "already up to date: $(version_string)"
    return 0
  fi

  download "$url" "$tmp/chromebrew-scripts" || return 1
  verify_sha256 "$tmp/chromebrew-scripts" "$sum" || return 1
  bash -n "$tmp/chromebrew-scripts" || { log_error "the downloaded file does not parse; $self left untouched"; return 1; }
  grep -q '^CBS_BUNDLED=1$' "$tmp/chromebrew-scripts" || { log_error "the downloaded file is not a single-file build of chromebrew-scripts; $self left untouched"; return 1; }
  new_ver=$(sed -n "s/^CBS_BUNDLE_VERSION='\\(.*\\)'$/\\1/p" "$tmp/chromebrew-scripts" | head -n1)
  new_commit=$(sed -n "s/^CBS_BUNDLE_COMMIT='\\(.*\\)'$/\\1/p" "$tmp/chromebrew-scripts" | head -n1)

  if [ "$CBS_DRY_RUN" = 1 ]; then
    log_dry "would replace $self: ${CBS_BUNDLE_VERSION:-?} (git ${CBS_BUNDLE_COMMIT:-?}) -> ${new_ver:-?} (git ${new_commit:-?})"
    return 0
  fi

  # Stage next to the target (same filesystem, so mv is an atomic rename),
  # as the file's owner; the temp copy must be readable by that owner.
  dir=$(dirname "$self")
  staged="$dir/.chromebrew-scripts.new.$$"
  chmod 0755 "$tmp" && chmod 0644 "$tmp/chromebrew-scripts"
  _su_as_owner "$self" install -m 0755 "$tmp/chromebrew-scripts" "$staged" || { log_error "could not write to $dir"; return 1; }
  if ! _su_as_owner "$self" mv -f -- "$staged" "$self"; then
    _su_as_owner "$self" rm -f -- "$staged"
    log_error "could not replace $self"
    return 1
  fi
  log_updated "updated ${CBS_BUNDLE_VERSION:-?} (git ${CBS_BUNDLE_COMMIT:-?}) -> ${new_ver:-?} (git ${new_commit:-?})"
  return 0
}

# selfupdate_main: entry for --self-update. Needs no ChromeOS.
selfupdate_main() {
  local repo branch root="$CBS_ROOT_DIR" target
  repo=$(cfg SELF_UPDATE_REPO)
  branch=$(cfg SELF_UPDATE_BRANCH)
  selfupdate_source_ok "$repo" || return 1
  log_step "self-update"
  # A root-owned installation is updated as root; ask for sudo once, up
  # front, instead of failing later inside `sudo -n`.
  if [ "${CBS_BUNDLED:-0}" = 1 ]; then target="$CBS_BIN"; else target="$root"; fi
  if ! is_root && [ "$(_su_owner "$target")" = root ]; then
    if ! _su_sudo; then
      log_error "$target is owned by root and ${CBS_SUDO:-sudo} is not available"
      return 1
    fi
    log_info "$target is owned by root; $CBS_SUDO is required to update it"
    # shellcheck disable=SC2086
    if ! $CBS_SUDO -n true 2>/dev/null && ! $CBS_SUDO -v; then
      log_error "$CBS_SUDO credentials unavailable; nothing changed"
      return 1
    fi
  fi
  if [ "${CBS_BUNDLED:-0}" = 1 ]; then
    selfupdate_bundle "$CBS_BIN" "$repo"
  elif [ -e "$root/.git" ]; then
    has_cmd git || { log_error "git is required to update a git checkout"; return 1; }
    if [ "${CBS_CFG_SOURCE[SELF_UPDATE_REPO]:-default}" = default ]; then
      # Nothing configured: a checkout follows the remote it was cloned from.
      local origin
      if origin=$(git -C "$root" remote get-url origin 2>/dev/null) && [ -n "$origin" ]; then
        selfupdate_origin_ok "$origin" || return 1
        repo="$origin"
        log_detail "no SELF_UPDATE_REPO configured; following the checkout's origin"
      fi
    fi
    selfupdate_git "$root" "$repo" "$branch"
  else
    selfupdate_tarball "$root" "$repo" "$branch"
  fi
}
