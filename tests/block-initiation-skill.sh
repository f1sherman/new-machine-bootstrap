#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
HOOK="$REPO_ROOT/roles/common/files/claude/hooks/block-initiation-skill-on-main.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"; git -c init.templateDir= init -qb main "$REPO" >/dev/null
git -C "$REPO" -c user.email=t@e -c user.name=t commit -q --allow-empty -m init

run() { # skill, config-file -> stdout
  printf '%s' "{\"tool_name\":\"Skill\",\"tool_input\":{\"skill\":\"$1\"}}" \
    | (cd "$REPO" && NMB_INITIATION_SKILLS_CONFIG="$2" "$HOOK")
}
fires() { run "$1" "$2" | jq -e '.hookSpecificOutput.additionalContext | test("repo-start")' >/dev/null 2>&1; }

# default config (absent file -> built-in superpowers defaults)
fires "superpowers:brainstorming" "/nonexistent" || { echo "FAIL default brainstorming"; exit 1; }
fires "superpowers:systematic-debugging" "/nonexistent" || { echo "FAIL default debugging"; exit 1; }
! fires "superpowers:writing-plans" "/nonexistent" || { echo "FAIL should be silent"; exit 1; }

# override config
OVR="$TMP/ovr.sh"; printf "NMB_BRAINSTORMING_SKILL='alt:design'\nNMB_DEBUGGING_SKILL='alt:debug'\n" > "$OVR"
fires "alt:design" "$OVR" || { echo "FAIL override design"; exit 1; }
fires "alt:debug" "$OVR" || { echo "FAIL override debug"; exit 1; }
! fires "superpowers:brainstorming" "$OVR" || { echo "FAIL old id should be silent under override"; exit 1; }
echo "PASS  block-initiation-skill test suite"
