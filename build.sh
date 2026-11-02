#!/usr/bin/env bash
# build.sh - make the single-file build of chromebrew-scripts.
#
#   ./build.sh [OUTPUT]            default OUTPUT: dist/chromebrew-scripts
#   ./build.sh -o OUTPUT | --output OUTPUT
#
# The entry point (bin/chromebrew-scripts) is copied with the block between
# its @@BUNDLE-MODULES-BEGIN@@ / -END@@ markers replaced by the contents of
# the modules it sources, in the same order. The entry point's
# `CBS_BUNDLED=0` line becomes `CBS_BUNDLED=1`; the version and the git
# commit are recorded at the top (CBS_BUNDLE_VERSION, CBS_BUNDLE_COMMIT) and
# the bash completion script is embedded for `--completion bash`. The result
# is plain bash: nothing is compiled, it needs the same bash 4.4 and
# coreutils as the multi-file version, and it is checked with bash -n.
set -euo pipefail

root=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)
out="$root/dist/chromebrew-scripts"
while [ $# -gt 0 ]; do
  case "$1" in
    -o|--output) [ -n "${2:-}" ] || { echo "build.sh: $1 needs a value" >&2; exit 2; }; out="$2"; shift ;;
    --output=*) out="${1#*=}" ;;
    -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "build.sh: unknown option: $1" >&2; exit 2 ;;
    *) out="$1" ;;
  esac
  shift
done
entry="$root/bin/chromebrew-scripts"

if ! grep -q '^# @@BUNDLE-MODULES-BEGIN@@$' "$entry" || ! grep -q '^# @@BUNDLE-MODULES-END@@$' "$entry" \
   || ! grep -q '^CBS_BUNDLED=0' "$entry"; then
  echo "build.sh: bundle markers not found in $entry" >&2
  exit 1
fi
# The modules the entry point sources, in its order.
# shellcheck disable=SC2016  # $CBS_ROOT_DIR is matched literally
mapfile -t modules < <(sed -n 's|^source "\$CBS_ROOT_DIR/\(lib/[^"]*\.sh\)"$|\1|p' "$entry")
[ ${#modules[@]} -gt 0 ] || { echo "build.sh: no modules found in $entry" >&2; exit 1; }

version=$(tr -d '[:space:]' < "$root/VERSION")
commit=unknown
if git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
  commit=$(git -C "$root" rev-parse --short HEAD)
  # Modified or untracked files under the bundled paths make it a -dirty build.
  [ -z "$(git -C "$root" status --porcelain -- bin lib completions VERSION 2>/dev/null)" ] || commit="$commit-dirty"
fi

# module FILE: a module's contents under a banner, without its shebang.
module() {
  printf '\n# ==== %s ====\n' "${1#"$root"/}"
  sed '1{/^#!/d}' "$1"
}

mkdir -p "$(dirname "$out")"
tmp=$(mktemp "$(dirname "$out")/.chromebrew-scripts.XXXXXX")
trap 'rm -f -- "$tmp"' EXIT
{
  inside=0
  lineno=0
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    if [ "$lineno" = 1 ]; then
      printf '%s\n' "$line"
      cat <<EOF
#
# Single-file build of chromebrew-scripts $version (git $commit), made by
# build.sh from https://github.com/uberhacker/chromebrew-scripts. Do not
# edit: change the modules in lib/ and rebuild.
CBS_BUNDLE_VERSION='$version'
CBS_BUNDLE_COMMIT='$commit'
EOF
      continue
    fi
    case "$line" in
      'CBS_BUNDLED=0'*)
        printf 'CBS_BUNDLED=1\n'
        continue ;;
      '# @@BUNDLE-MODULES-BEGIN@@')
        inside=1
        for m in "${modules[@]}"; do
          module "$root/$m"
        done
        printf '\n# ==== completions/chromebrew-scripts.bash (for --completion bash) ====\n'
        printf "cbs_completion_script() {\n  cat <<'CBS_COMPLETION_EOF'\n"
        cat "$root/completions/chromebrew-scripts.bash"
        printf 'CBS_COMPLETION_EOF\n}\n'
        printf '# ==== end of modules ====\n'
        continue ;;
      '# @@BUNDLE-MODULES-END@@')
        inside=0
        continue ;;
    esac
    [ "$inside" = 1 ] || printf '%s\n' "$line"
  done < "$entry"
} > "$tmp"

bash -n "$tmp" || { echo "build.sh: the result does not parse" >&2; exit 1; }
chmod 0755 "$tmp"
mv -f -- "$tmp" "$out"
trap - EXIT
printf 'built %s (%s, git %s, %s modules, %s lines)\n' "$out" "$version" "$commit" "${#modules[@]}" "$(wc -l < "$out")"
