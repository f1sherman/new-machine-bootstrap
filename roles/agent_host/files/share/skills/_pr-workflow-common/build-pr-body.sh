#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF' >&2
Usage: build-pr-body.sh --context-json <path> --summary <text> --why <text> [--evidence <text> ...] --approach <text> [--verification <text> ...] [--reviewer-notes <text>]
EOF
}

context_json=""
summary=""
why_text=""
approach_text=""
reviewer_notes=""
scope_lines=()
evidence_items=()
verification_items=()

option_requires_value() {
  local option="$1"
  local value="${2-}"

  if [[ -z "$value" || "$value" == --* ]]; then
    echo "Error: $option requires a value" >&2
    usage
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --context-json)
      option_requires_value "$1" "${2-}"
      context_json="$2"
      shift 2
      ;;
    --summary)
      option_requires_value "$1" "${2-}"
      summary="$2"
      shift 2
      ;;
    --why)
      option_requires_value "$1" "${2-}"
      why_text="$2"
      shift 2
      ;;
    --evidence)
      option_requires_value "$1" "${2-}"
      evidence_items+=("$2")
      shift 2
      ;;
    --approach)
      option_requires_value "$1" "${2-}"
      approach_text="$2"
      shift 2
      ;;
    --verification)
      option_requires_value "$1" "${2-}"
      verification_items+=("$2")
      shift 2
      ;;
    --reviewer-notes)
      option_requires_value "$1" "${2-}"
      reviewer_notes="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

[[ -n "$context_json" ]] || { echo "Error: --context-json is required" >&2; usage; exit 1; }
[[ -f "$context_json" ]] || { echo "Error: context JSON not found: $context_json" >&2; exit 1; }
[[ -n "$summary" ]] || { echo "Error: --summary is required" >&2; usage; exit 1; }
[[ -n "$why_text" ]] || { echo "Error: --why is required" >&2; usage; exit 1; }
[[ -n "$approach_text" ]] || { echo "Error: --approach is required" >&2; usage; exit 1; }

# Validate the shared context payload up front so callers fail early on stale or malformed input.
jq -e . "$context_json" >/dev/null
while IFS= read -r scope_line; do
  scope_line="$(printf '%s' "$scope_line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  [[ -n "$scope_line" ]] || continue
  scope_lines+=("$scope_line")
done < <(jq -r '.diff_stat // ""' "$context_json")
reviewer_notes="$(printf '%s' "$reviewer_notes" | tr '\r\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')"

printf '## Summary\n\n%s\n\n' "$summary"
if [[ "${#scope_lines[@]}" -eq 1 ]]; then
  printf 'Scope: %s\n\n' "${scope_lines[0]}"
elif [[ "${#scope_lines[@]}" -gt 1 ]]; then
  printf 'Scope:\n'
  for scope_line in "${scope_lines[@]}"; do
    printf -- '- %s\n' "$scope_line"
  done
  printf '\n'
fi

printf '## Why\n\n%s\n' "$why_text"
if [[ "${#evidence_items[@]}" -gt 0 ]]; then
  printf '\n'
  for item in "${evidence_items[@]}"; do
    printf -- '- %s\n' "$item"
  done
fi

printf '\n## Approach\n\n%s\n' "$approach_text"

printf '\n## Verification\n\n'
if [[ "${#verification_items[@]}" -eq 0 ]]; then
  printf -- '- Not run\n'
else
  for item in "${verification_items[@]}"; do
    printf -- '- `%s`\n' "$item"
  done
fi

if [[ -n "$reviewer_notes" ]]; then
  printf '\nReviewer Notes: %s\n' "$reviewer_notes"
fi
