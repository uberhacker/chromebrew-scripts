#!/usr/bin/env bash
# Generic stub: log the call, exit with $STUB_EXIT_<name> (default 0).
name="$(basename "$0")"
printf '%s %s\n' "${name}" "$*" >> "${STUB_LOG:-/dev/null}"
var="STUB_EXIT_${name//[^A-Za-z0-9]/_}"
exit "${!var:-0}"
