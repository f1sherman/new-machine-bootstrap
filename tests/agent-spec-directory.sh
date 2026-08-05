#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
HELPER="$REPO_ROOT/roles/common/files/bin/agent-spec-directory"
TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

fail() { printf 'FAIL  %s\n' "$1" >&2; exit 1; }
assert_eq() { [ "$1" = "$2" ] || fail "$3: expected $1, got $2"; printf 'PASS  %s\n' "$3"; }
assert_invalid() {
  local value="$1" name="$2" output
  printf '%s\n' "$value" > "$TMPROOT/config/new-machine-bootstrap/spec-directory"
  if output="$(XDG_CONFIG_HOME="$TMPROOT/config" "$HELPER" 2>&1)"; then
    fail "$name: expected failure"
  fi
  [[ "$output" == *"invalid spec directory"* ]] || fail "$name: missing validation error"
  printf 'PASS  %s\n' "$name"
}

mkdir -p "$TMPROOT/config/new-machine-bootstrap"
assert_eq 'docs/superpowers/specs' "$(XDG_CONFIG_HOME="$TMPROOT/config" "$HELPER")" 'absent config uses default'
: > "$TMPROOT/config/new-machine-bootstrap/spec-directory"
assert_eq 'docs/superpowers/specs' "$(XDG_CONFIG_HOME="$TMPROOT/config" "$HELPER")" 'empty config uses default'
printf '%s\n' './docs/.solution-designs/' > "$TMPROOT/config/new-machine-bootstrap/spec-directory"
assert_eq 'docs/.solution-designs' "$(XDG_CONFIG_HOME="$TMPROOT/config" "$HELPER")" 'configured path is normalized'
assert_invalid '/tmp/specs' 'absolute path is rejected'
assert_invalid '../specs' 'parent prefix is rejected'
assert_invalid 'docs/../specs' 'parent component is rejected'
assert_invalid './' 'empty normalized path is rejected'
printf 'agent-spec-directory checks complete\n'
