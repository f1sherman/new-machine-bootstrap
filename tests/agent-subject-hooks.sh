#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
CLAUDE_HOOK="$REPO_ROOT/roles/common/files/claude/hooks/remind-agent-subject-on-skill.sh"

ISO_CFG="$(mktemp)"; printf "NMB_BRAINSTORMING_SKILL='superpowers:brainstorming'\nNMB_DEBUGGING_SKILL='superpowers:systematic-debugging'\n" > "$ISO_CFG"
export NMB_INITIATION_SKILLS_CONFIG="$ISO_CFG"
CODEX_HOOK="$REPO_ROOT/roles/common/files/bin/codex-remind-agent-subject-on-prompt"

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"; rm -f "$ISO_CFG" "${OVR_CFG:-}"' EXIT

pass_case() { printf 'PASS  %s\n' "$1"; }
fail_case() { printf 'FAIL  %s\n%s\n' "$1" "$2" >&2; exit 1; }

assert_contains() {
  local haystack="$1" needle="$2" name="$3"
  [[ "$haystack" == *"$needle"* ]] || fail_case "$name" "missing '$needle' in: $haystack"
  pass_case "$name"
}

assert_empty() {
  local value="$1" name="$2"
  [[ -z "$value" ]] || fail_case "$name" "expected empty, got: $value"
  pass_case "$name"
}

assert_not_contains() {
  local haystack="$1" needle="$2" name="$3"
  [[ "$haystack" != *"$needle"* ]] || fail_case "$name" "unexpected '$needle' in: $haystack"
  pass_case "$name"
}

make_tmux_stub() {
  local subject="$1" stale="$2" stubdir="$3"
  mkdir -p "$stubdir"
  cat >"$stubdir/tmux" <<STUB
#!/usr/bin/env bash
case "\$1" in
  show-options)
    case "\${*: -1}" in
      @agent_subject) printf '%s' "$subject" ;;
      @agent_subject_stale) printf '%s' "$stale" ;;
    esac
    ;;
esac
STUB
  chmod +x "$stubdir/tmux"
}

stub_missing="$TMPROOT/missing"
make_tmux_stub "" "" "$stub_missing"
claude_out="$(printf '%s' '{"tool_name":"Skill","tool_input":{"skill":"superpowers:brainstorming"}}' | TMUX=1 TMUX_PANE=%1 PATH="$stub_missing:$PATH" "$CLAUDE_HOOK")"
assert_contains "$claude_out" "tmux-agent-subject set" "Claude skill hook reminds when subject missing"
assert_contains "$claude_out" "superpowers:brainstorming" "Claude reminder names triggering skill"
assert_not_contains "$claude_out" "tmux-agent-subject clear" "Claude reminder does not offer non-persistent clear opt-out"

claude_other="$(printf '%s' '{"tool_name":"Skill","tool_input":{"skill":"superpowers:writing-plans"}}' | TMUX=1 TMUX_PANE=%1 PATH="$stub_missing:$PATH" "$CLAUDE_HOOK")"
assert_empty "$claude_other" "Claude hook ignores non-initiating skills"

stub_set="$TMPROOT/set"
make_tmux_stub "existing subject" "" "$stub_set"
claude_set="$(printf '%s' '{"tool_name":"Skill","tool_input":{"skill":"superpowers:systematic-debugging"}}' | TMUX=1 TMUX_PANE=%1 PATH="$stub_set:$PATH" "$CLAUDE_HOOK")"
assert_empty "$claude_set" "Claude hook skips when subject current"

stub_stale="$TMPROOT/stale"
make_tmux_stub "old subject" "1" "$stub_stale"
codex_out="$(printf '%s' '{"prompt":"$superpowers:systematic-debugging this failure"}' | TMUX=1 TMUX_PANE=%1 PATH="$stub_stale:$PATH" "$CODEX_HOOK")"
assert_contains "$codex_out" "tmux-agent-subject set" "Codex prompt hook reminds when subject stale"
assert_contains "$codex_out" "systematic-debugging" "Codex reminder names triggering prompt skill"
assert_not_contains "$codex_out" "tmux-agent-subject clear" "Codex reminder does not offer non-persistent clear opt-out"

codex_other="$(printf '%s' '{"prompt":"hello"}' | TMUX=1 TMUX_PANE=%1 PATH="$stub_missing:$PATH" "$CODEX_HOOK")"
assert_empty "$codex_other" "Codex hook ignores unrelated prompts"

codex_mention="$(printf '%s' '{"prompt":"please compare superpowers:brainstorming docs"}' | TMUX=1 TMUX_PANE=%1 PATH="$stub_missing:$PATH" "$CODEX_HOOK")"
assert_empty "$codex_mention" "Codex hook ignores mid-sentence skill mentions"

OVR_CFG="$(mktemp)"; printf "NMB_BRAINSTORMING_SKILL='alt:design'\nNMB_DEBUGGING_SKILL='alt:debug'\n" > "$OVR_CFG"
claude_ovr="$(printf '%s' '{"tool_name":"Skill","tool_input":{"skill":"alt:design"}}' | TMUX=1 TMUX_PANE=%1 NMB_INITIATION_SKILLS_CONFIG="$OVR_CFG" PATH="$stub_missing:$PATH" "$CLAUDE_HOOK")"
assert_contains "$claude_ovr" "alt:design" "Claude reminder fires for overridden skill id"
claude_old="$(printf '%s' '{"tool_name":"Skill","tool_input":{"skill":"superpowers:brainstorming"}}' | TMUX=1 TMUX_PANE=%1 NMB_INITIATION_SKILLS_CONFIG="$OVR_CFG" PATH="$stub_missing:$PATH" "$CLAUDE_HOOK" || true)"
assert_empty "$claude_old" "Claude reminder silent for old id under override"

printf 'agent subject hook checks complete\n'
