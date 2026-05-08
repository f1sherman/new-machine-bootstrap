#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(git -C "$script_dir" rev-parse --show-toplevel)"
workflow_dir="$repo_root/.github/workflows"

pass=0
fail=0

pass_case() {
  pass=$((pass + 1))
  printf 'PASS  %s\n' "$1"
}

fail_case() {
  fail=$((fail + 1))
  printf 'FAIL  %s\n' "$1"
  printf '      %s\n' "$2"
}

resolve_yq() {
  if command -v yq >/dev/null 2>&1; then
    command -v yq
  elif [ -x "$HOME/.local/bin/yq" ]; then
    printf '%s\n' "$HOME/.local/bin/yq"
  else
    return 1
  fi
}

yq_bin="$(resolve_yq)" || {
  fail_case "CI test inventory can parse workflow YAML" "missing yq"
  printf '\n%d passed, %d failed\n' "$pass" "$fail"
  exit 1
}

tracked_tests=()
while IFS= read -r test_path; do
  tracked_tests+=("$test_path")
done < <(
  git -C "$repo_root" ls-files |
    rg '(^tests/|\.test$|_test\.|\.spec\.|\.test\.)' |
    sort
)

workflow_runs="$(
  find "$workflow_dir" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) -print0 |
    sort -z |
    xargs -0 "$yq_bin" -r '.jobs.*.steps[]? | .run // ""'
)"

missing=()
for test_path in "${tracked_tests[@]}"; do
  if ! printf '%s\n' "$workflow_runs" | rg -F -- "$test_path" >/dev/null 2>&1; then
    missing+=("$test_path")
  fi
done

if [ "${#missing[@]}" -eq 0 ]; then
  pass_case "every tracked test-like file is referenced by CI"
else
  fail_case \
    "every tracked test-like file is referenced by CI" \
    "$(printf 'not referenced: %s\n' "${missing[@]}")"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
