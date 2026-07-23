#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
template="$repo_root/roles/common/templates/dotfiles/gitignore"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() {
  printf 'FAIL  %s\n' "$1" >&2
  exit 1
}

count="$(grep -Fxc '**/.pi/remote-pi/' "$template" || true)"
[[ "$count" == "1" ]] || fail "managed global ignore must contain exactly one recursive Remote Pi rule"

if grep -Fxq '.pi/' "$template"; then
  fail "managed global ignore must not hide all .pi project configuration"
fi

git -C "$tmp" init -q
mkdir -p "$tmp/.pi/remote-pi" "$tmp/nested/.pi/remote-pi" "$tmp/nested/.pi"
touch "$tmp/.pi/remote-pi/config.json" "$tmp/nested/.pi/remote-pi/config.json" "$tmp/nested/.pi/project-config.json"

root_match="$(git -c core.excludesFile="$template" -C "$tmp" check-ignore -v --no-index .pi/remote-pi/config.json || true)"
nested_match="$(git -c core.excludesFile="$template" -C "$tmp" check-ignore -v --no-index nested/.pi/remote-pi/config.json || true)"
[[ -n "$root_match" ]] || fail "Remote Pi runtime at repository root must be ignored"
[[ -n "$nested_match" ]] || fail "Remote Pi runtime below a repository subdirectory must be ignored"

if git -c core.excludesFile="$template" -C "$tmp" check-ignore -q --no-index nested/.pi/project-config.json; then
  fail "other nested .pi project configuration must remain visible"
fi

printf 'PASS  managed global ignore targets Remote Pi runtime state at any depth\n'

# Pi subagents run artifacts are per-repository runtime state and must be
# ignored at any depth, without hiding real .pi project configuration.
mkdir -p "$tmp/.pi-subagents/artifacts" "$tmp/nested/.pi-subagents/artifacts"
touch "$tmp/.pi-subagents/artifacts/run.md" "$tmp/nested/.pi-subagents/artifacts/run.md"

sub_root="$(git -c core.excludesFile="$template" -C "$tmp" check-ignore -v --no-index .pi-subagents/artifacts/run.md || true)"
sub_nested="$(git -c core.excludesFile="$template" -C "$tmp" check-ignore -v --no-index nested/.pi-subagents/artifacts/run.md || true)"
[[ -n "$sub_root" ]] || fail "Pi subagents artifacts at repository root must be ignored"
[[ -n "$sub_nested" ]] || fail "Pi subagents artifacts below a repository subdirectory must be ignored"

if git -c core.excludesFile="$template" -C "$tmp" check-ignore -q --no-index nested/.pi/project-config.json; then
  fail "the .pi-subagents rule must not hide .pi project configuration"
fi

printf 'PASS  managed global ignore targets Pi subagents run artifacts at any depth\n'
