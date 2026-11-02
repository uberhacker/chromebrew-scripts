#!/usr/bin/env bash
# tests/lint.sh - bash -n on every script, shellcheck -x, and a build.
#
# The entry point is checked with -x so the whole program (core and command
# modules are sourced statically) is analysed as one unit. The single-file
# build is assembled into a temporary file and checked on its own too.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"

rc=0
for f in bin/chromebrew-scripts install.sh build.sh tests/*.sh tests/test_helper.bash \
         tests/stubs/curl tests/stubs/sudo tests/stubs/crew tests/stubs/crossystem tests/stubs/stub.sh \
         completions/*.bash lib/core/*.sh lib/cmd/*.sh; do
  bash -n "$f" || { echo "bash -n failed: $f"; rc=1; }
done

bundle=$(mktemp -d)
trap 'rm -rf -- "$bundle"' EXIT
./build.sh "$bundle/chromebrew-scripts" >/dev/null || { echo "build.sh failed"; rc=1; }

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -x bin/chromebrew-scripts install.sh build.sh tests/*.sh tests/test_helper.bash \
    tests/stubs/curl tests/stubs/sudo tests/stubs/crew tests/stubs/crossystem tests/stubs/stub.sh || rc=1
  shellcheck -s bash completions/*.bash || rc=1
  # SC2317 (unreachable) is noise in the single file: the command and step
  # functions are dispatched by name.
  [ -f "$bundle/chromebrew-scripts" ] && { shellcheck -e SC2317 "$bundle/chromebrew-scripts" || rc=1; }
else
  echo "shellcheck not installed; skipped" >&2
fi

[ "$rc" -eq 0 ] && echo "lint ok"
exit "$rc"
