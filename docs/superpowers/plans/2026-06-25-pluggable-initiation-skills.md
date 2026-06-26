# Pluggable initiation-skills + superpowers-plugin opt-out Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make nmb's superpowers Claude-plugin install opt-out-able and make the two initiation-skill identifiers overridable, so a downstream provisioner can point nmb's CLAUDE.md base fragment and all behavioral hooks (Claude + Codex) at an alternate skill library — with defaults unchanged.

**Architecture:** Three env vars (`NMB_INSTALL_SUPERPOWERS_PLUGIN`, `NMB_BRAINSTORMING_SKILL`, `NMB_DEBUGGING_SKILL`) become Ansible facts with superpowers defaults. The plugin loop is gated on the boolean. The skill ids drive a generated, sourced shell config (`~/.claude/hooks/initiation-skills.sh`); every consuming hook sources it (with built-in superpowers defaults so it is correct when the config is absent) and builds its `case`/regex patterns from it. The base CLAUDE.md fragment becomes a Jinja2 template.

**Tech Stack:** Ansible (YAML), bash hook scripts, Ruby (`_recover-agent-sessions`), `jq`, bash `.test`/`.sh` test harnesses wired into `.github/workflows/integration-test.yml`.

## Global Constraints

- nmb is a **public** repository. Do NOT introduce company names, internal repo names, employee handles, internal marketplace/plugin names, or internal tooling references anywhere in this repo. Describe the downstream consumer abstractly. (Concrete consumer steps live in a private downstream provisioner's own spec.)
- Defaults must preserve today's behavior exactly: `NMB_INSTALL_SUPERPOWERS_PLUGIN=true`, `NMB_BRAINSTORMING_SKILL=superpowers:brainstorming`, `NMB_DEBUGGING_SKILL=superpowers:systematic-debugging`. An unset environment produces no behavior change and no provision diff beyond the new (default-valued) config file.
- No backwards-compatibility dual-matching: each hook matches exactly the configured ids, not "old OR new".
- Comments: sparingly, explain why not what. Ruby for scripts, bash for snippets. `jq`/`yq` for JSON/YAML, never python/ruby for parsing.
- Hook scripts are run **in-repo** by the test suite, so they must never depend on the user's real `~/.claude/hooks/initiation-skills.sh`. Tests set `NMB_INITIATION_SKILLS_CONFIG` to a controlled temp path for isolation (mirrors existing tmux-state isolation in these tests).
- Every tracked test file (`^tests/` or `*.test`) MUST be referenced by a `run:` step in a workflow under `.github/workflows/`, or `tests/ci-test-inventory.sh` fails.
- Working dir: the git worktree at `.worktrees/superpowers-install-seam` (branch `superpowers-install-seam`). Commit with the `_commit` skill / `_committer` agent (a PreToolUse hook blocks raw `git commit`).

## File Structure

- `roles/common/tasks/main.yml` — add fact-resolution task; gate plugin loop; add config-write task; switch `00-base.md` copy→template.
- `roles/common/templates/claude/CLAUDE.md.d/00-base.md.j2` — NEW: templated base fragment (moved from `files/`).
- `roles/common/templates/claude/hooks/initiation-skills.sh.j2` — NEW: generated sourced config.
- `roles/common/files/claude/hooks/block-initiation-skill-on-main.sh` — source config; case from full ids.
- `roles/common/files/claude/hooks/remind-agent-subject-on-skill.sh` — source config; case from full ids.
- `roles/common/files/claude/hooks/remind-repo-start-on-dev-prompt.sh` — source config; regex from verbs.
- `roles/common/files/bin/codex-remind-agent-subject-on-prompt` — source config; regex from full ids.
- `roles/common/files/bin/codex-remind-repo-start-on-dev-prompt` — source config; regex from verbs.
- `roles/common/files/bin/_recover-agent-sessions` — read brainstorming verb from config for the cosmetic strip.
- `roles/common/files/claude/hooks/remind-repo-start-on-dev-prompt.sh.test` — add override cases.
- `tests/agent-subject-hooks.sh` — isolate config; add override cases.
- `tests/block-initiation-skill.sh` — NEW: focused test for the block-initiation hook (default + override).
- `.github/workflows/integration-test.yml` — wire the new test.

## Shared config-sourcing snippet (referenced by several tasks)

Every bash consumer gets this block immediately after `set -euo pipefail` (Codex agent-subject hook has no `set` line change — insert after its `set -euo pipefail` too). Built-in defaults match superpowers so the script is correct when no config file exists:

```bash
# Initiation-skill identifiers. Defaults match superpowers; a generated
# config (written by the provisioner) overrides them. NMB_INITIATION_SKILLS_CONFIG
# lets tests point at a controlled file instead of the deployed one.
NMB_BRAINSTORMING_SKILL='superpowers:brainstorming'
NMB_DEBUGGING_SKILL='superpowers:systematic-debugging'
_init_cfg="${NMB_INITIATION_SKILLS_CONFIG:-$HOME/.claude/hooks/initiation-skills.sh}"
[ -f "$_init_cfg" ] && . "$_init_cfg"
NMB_BRAINSTORMING_VERB="${NMB_BRAINSTORMING_SKILL##*:}"
NMB_DEBUGGING_VERB="${NMB_DEBUGGING_SKILL##*:}"
```

---

### Task A1: Resolve override facts + gate the superpowers plugin install

**Files:**
- Modify: `roles/common/tasks/main.yml` (add fact task before the plugin loop ~line 714; edit the loop)

**Interfaces:**
- Produces: facts `install_superpowers_plugin` (bool), `brainstorming_skill` (str), `debugging_skill` (str) for all later tasks.

- [ ] **Step 1: Add the fact-resolution task** near the top of the common task file (after fact gathering, before first consumer — place just before the "Install base ~/.claude/CLAUDE.md fragment" task so both Part A and Part B can use the facts):

```yaml
- name: Resolve initiation-skill identifiers and plugin opt-out (overridable by downstream provisioners)
  set_fact:
    install_superpowers_plugin: "{{ (lookup('env', 'NMB_INSTALL_SUPERPOWERS_PLUGIN') | default('true', true)) | bool }}"
    brainstorming_skill: "{{ lookup('env', 'NMB_BRAINSTORMING_SKILL') | default('superpowers:brainstorming', true) }}"
    debugging_skill: "{{ lookup('env', 'NMB_DEBUGGING_SKILL') | default('superpowers:systematic-debugging', true) }}"
```

- [ ] **Step 2: Gate the plugin loop.** Replace the static `loop:` in the "Install Claude Code plugins" task so superpowers is conditional:

```yaml
- name: Install Claude Code plugins
  command: claude plugin install {{ item }} --scope user
  loop: "{{ ['pr-review-toolkit@claude-plugins-official'] + (['superpowers@claude-plugins-official'] if install_superpowers_plugin else []) }}"
  register: claude_plugin_result
  changed_when: "'already installed' not in (claude_plugin_result.stdout | default(''))"
  failed_when: false
```

- [ ] **Step 3: Verify the rendered list both ways** (manual e2e — Ansible conditionals have no useful unit test). Run from the worktree root:

```bash
ansible localhost -m debug -a "msg={{ ['pr-review-toolkit@claude-plugins-official'] + (['superpowers@claude-plugins-official'] if (install_superpowers_plugin | default('true','true') if false else (lookup('env','NMB_INSTALL_SUPERPOWERS_PLUGIN') | default('true', true)) | bool) else []) }}"
```

Simpler, run the actual expression with env unset then set:

```bash
ansible localhost -m debug -a "msg={{ (lookup('env','NMB_INSTALL_SUPERPOWERS_PLUGIN') | default('true', true)) | bool }}"
NMB_INSTALL_SUPERPOWERS_PLUGIN=false ansible localhost -m debug -a "msg={{ (lookup('env','NMB_INSTALL_SUPERPOWERS_PLUGIN') | default('true', true)) | bool }}"
```
Expected: first prints `true`, second prints `false`.

- [ ] **Step 4: Commit** (via `_commit` skill). Message: `feat(claude): gate superpowers plugin install behind NMB_INSTALL_SUPERPOWERS_PLUGIN`.

---

### Task B1: Generated initiation-skills config + write task

**Files:**
- Create: `roles/common/templates/claude/hooks/initiation-skills.sh.j2`
- Modify: `roles/common/tasks/main.yml` (add write task after "Install Claude hooks")

**Interfaces:**
- Produces: `~/.claude/hooks/initiation-skills.sh` exporting `NMB_BRAINSTORMING_SKILL` / `NMB_DEBUGGING_SKILL`, consumed by Tasks B2–B6.

- [ ] **Step 1: Create the template** `roles/common/templates/claude/hooks/initiation-skills.sh.j2`:

```bash
# generated by new-machine-bootstrap — do not edit
NMB_BRAINSTORMING_SKILL='{{ brainstorming_skill }}'
NMB_DEBUGGING_SKILL='{{ debugging_skill }}'
```

- [ ] **Step 2: Add the write task** in `roles/common/tasks/main.yml` immediately after the "Install Claude hooks" task (so `~/.claude/hooks/` exists):

```yaml
- name: Write initiation-skills hook config
  template:
    src: '{{ playbook_dir }}/roles/common/templates/claude/hooks/initiation-skills.sh.j2'
    dest: '{{ ansible_facts["user_dir"] }}/.claude/hooks/initiation-skills.sh'
    mode: '0644'
```

- [ ] **Step 3: Verify render.** Run:

```bash
ansible localhost -m template -a "src=roles/common/templates/claude/hooks/initiation-skills.sh.j2 dest=/tmp/init-skills-check.sh" -e brainstorming_skill=superpowers:brainstorming -e debugging_skill=superpowers:systematic-debugging
. /tmp/init-skills-check.sh && echo "$NMB_BRAINSTORMING_SKILL | $NMB_DEBUGGING_SKILL"
```
Expected: `superpowers:brainstorming | superpowers:systematic-debugging`. Then `rm /tmp/init-skills-check.sh`.

- [ ] **Step 4: Commit.** Message: `feat(claude): generate sourced initiation-skills hook config`.

---

### Task B2: Make the two `case`-based Claude hooks configurable + test

**Files:**
- Modify: `roles/common/files/claude/hooks/block-initiation-skill-on-main.sh`
- Modify: `roles/common/files/claude/hooks/remind-agent-subject-on-skill.sh`
- Modify: `tests/agent-subject-hooks.sh`
- Create: `tests/block-initiation-skill.sh`
- Modify: `.github/workflows/integration-test.yml`

**Interfaces:**
- Consumes: config from Task B1 / the shared snippet.

- [ ] **Step 1: Write the failing test** for the block-initiation hook. Create `tests/block-initiation-skill.sh`:

```bash
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
```

- [ ] **Step 2: Run it, expect failure** (hook still hardcodes ids; override cases fail):

```bash
chmod +x tests/block-initiation-skill.sh && bash tests/block-initiation-skill.sh
```
Expected: `FAIL override design` (the `alt:design` skill is not matched yet).

- [ ] **Step 3: Edit `block-initiation-skill-on-main.sh`.** Insert the shared config-sourcing snippet after line 5 (`set -euo pipefail`). Change the `case` (currently line 16) to:

```bash
case "$skill" in
  "$NMB_BRAINSTORMING_SKILL"|"$NMB_DEBUGGING_SKILL"|_spec-first|_spec-to-pr|_fix) ;;
  *) exit 0 ;;
esac
```

- [ ] **Step 4: Run the new test, expect pass:**

```bash
bash tests/block-initiation-skill.sh
```
Expected: `PASS  block-initiation-skill test suite`.

- [ ] **Step 5: Edit `remind-agent-subject-on-skill.sh`.** Insert the shared snippet after line 2 (`set -euo pipefail`). Change the `case` (currently line 14) to:

```bash
case "$skill" in
  "$NMB_BRAINSTORMING_SKILL"|"$NMB_DEBUGGING_SKILL") ;;
  *) exit 0 ;;
esac
```

- [ ] **Step 6: Update `tests/agent-subject-hooks.sh` for isolation + override.** At the top after `REPO_ROOT=...`, force a controlled default config so the suite never reads the user's real one:

```bash
ISO_CFG="$(mktemp)"; printf "NMB_BRAINSTORMING_SKILL='superpowers:brainstorming'\nNMB_DEBUGGING_SKILL='superpowers:systematic-debugging'\n" > "$ISO_CFG"
export NMB_INITIATION_SKILLS_CONFIG="$ISO_CFG"
trap 'rm -f "$ISO_CFG" "${OVR_CFG:-}"' EXIT
```
Then append an override block after the existing assertions:

```bash
OVR_CFG="$(mktemp)"; printf "NMB_BRAINSTORMING_SKILL='alt:design'\nNMB_DEBUGGING_SKILL='alt:debug'\n" > "$OVR_CFG"
claude_ovr="$(printf '%s' '{"tool_name":"Skill","tool_input":{"skill":"alt:design"}}' | TMUX=1 TMUX_PANE=%1 NMB_INITIATION_SKILLS_CONFIG="$OVR_CFG" PATH="$stub_missing:$PATH" "$CLAUDE_HOOK")"
assert_contains "$claude_ovr" "alt:design" "Claude reminder fires for overridden skill id"
claude_old="$(printf '%s' '{"tool_name":"Skill","tool_input":{"skill":"superpowers:brainstorming"}}' | TMUX=1 TMUX_PANE=%1 NMB_INITIATION_SKILLS_CONFIG="$OVR_CFG" PATH="$stub_missing:$PATH" "$CLAUDE_HOOK" || true)"
assert_empty "$claude_old" "Claude reminder silent for old id under override"
```
(If `assert_empty` does not exist in the file, add a small helper that fails if its first arg is non-empty. Check the file's existing helpers first and reuse them.)

- [ ] **Step 7: Run the agent-subject suite, expect pass:**

```bash
bash tests/agent-subject-hooks.sh
```
Expected: all PASS including the new override assertions.

- [ ] **Step 8: Wire the new test into CI.** In `.github/workflows/integration-test.yml`, add a step mirroring the existing `agent-subject-hooks.sh` step:

```yaml
      - name: Run block-initiation-skill hook test
        run: bash tests/block-initiation-skill.sh
```

- [ ] **Step 9: Verify the CI inventory test passes:**

```bash
bash tests/ci-test-inventory.sh
```
Expected: no missing tests.

- [ ] **Step 10: Commit.** Message: `feat(hooks): make case-based initiation hooks configurable`.

---

### Task B3: Make the repo-start reminder hooks (Claude + Codex) configurable + test

**Files:**
- Modify: `roles/common/files/claude/hooks/remind-repo-start-on-dev-prompt.sh`
- Modify: `roles/common/files/bin/codex-remind-repo-start-on-dev-prompt`
- Modify: `roles/common/files/claude/hooks/remind-repo-start-on-dev-prompt.sh.test`

**Interfaces:**
- Consumes: config / shared snippet (uses `NMB_*_VERB`).

- [ ] **Step 1: Add failing override cases to `remind-repo-start-on-dev-prompt.sh.test`.** After the existing `run_reminder_case`/`run_silent_case` calls, add an override section. First, near the top (after the `unset TMUX_PANE ...` isolation line) pin a default config so the suite ignores the user's real one:

```bash
ISO_CFG="$(mktemp)"; printf "NMB_BRAINSTORMING_SKILL='superpowers:brainstorming'\nNMB_DEBUGGING_SKILL='superpowers:systematic-debugging'\n" > "$ISO_CFG"
export NMB_INITIATION_SKILLS_CONFIG="$ISO_CFG"
```
(Extend the existing `trap` to also `rm -f "$ISO_CFG" "${OVR_CFG:-}"`.) Then add override cases. Because `run_reminder_case`/`run_silent_case` run `$SCRIPT` directly, set the override config via a wrapper around those calls:

```bash
OVR_CFG="$(mktemp)"; printf "NMB_BRAINSTORMING_SKILL='alt:solution-design'\nNMB_DEBUGGING_SKILL='alt:root-cause-debugging'\n" > "$OVR_CFG"
NMB_INITIATION_SKILLS_CONFIG="$OVR_CFG" run_reminder_case "override: reminds for solution-design verb on main" "use alt:solution-design please" "main"
NMB_INITIATION_SKILLS_CONFIG="$OVR_CFG" run_reminder_case "override: reminds for root-cause-debugging verb on main" "alt:root-cause-debugging the test" "main"
NMB_INITIATION_SKILLS_CONFIG="$OVR_CFG" run_silent_case "override: silent for old brainstorming verb on main" "/superpowers:brainstorming check the dashboard" "main"
```
(Confirm `run_reminder_case`/`run_silent_case` are plain functions invoked as commands so the per-call env assignment applies to `$SCRIPT`. They are — `output="$(cd "$repo" && printf ... | "$SCRIPT")"` runs in the function's env.)

- [ ] **Step 2: Run it, expect failure:**

```bash
bash roles/common/files/claude/hooks/remind-repo-start-on-dev-prompt.sh.test
```
Expected: `FAIL  override: reminds for solution-design verb on main` (verb not matched yet; the script still uses literal `brainstorming|systematic-debugging`).

- [ ] **Step 3: Edit `remind-repo-start-on-dev-prompt.sh`.** Insert the shared snippet after line 12 (`set -euo pipefail`). Replace the literal `skill_pattern` (line 49) with one built from the verbs:

```bash
skill_pattern="(^|[^[:alnum:]_])(_fix|_spec-first|_spec-to-pr|${NMB_DEBUGGING_VERB}|${NMB_BRAINSTORMING_VERB})([^[:alnum:]_]|\$)"
```
(Note the escaped `\$` so the trailing anchor survives double-quote expansion.)

- [ ] **Step 4: Apply the identical change to `codex-remind-repo-start-on-dev-prompt`** (insert snippet after its `set -euo pipefail` line 11; same `skill_pattern` replacement at line 48). This script has no standalone test; it is a line-for-line mirror, so correctness rides on the Claude test + manual check in Step 6.

- [ ] **Step 5: Run the test, expect pass:**

```bash
bash roles/common/files/claude/hooks/remind-repo-start-on-dev-prompt.sh.test
```
Expected: full suite PASS including override cases.

- [ ] **Step 6: Manual parity check on the Codex mirror:**

```bash
tmpd=$(mktemp -d); git -C "$tmpd" -c init.templateDir= init -qb main >/dev/null; git -C "$tmpd" -c user.email=t@e -c user.name=t commit -q --allow-empty -m i
ovr=$(mktemp); printf "NMB_BRAINSTORMING_SKILL='alt:solution-design'\nNMB_DEBUGGING_SKILL='alt:root-cause-debugging'\n" > "$ovr"
printf '{"prompt":"use alt:solution-design now"}' | (cd "$tmpd" && NMB_INITIATION_SKILLS_CONFIG="$ovr" roles/common/files/bin/codex-remind-repo-start-on-dev-prompt) | jq -e '.hookSpecificOutput.additionalContext|test("repo-start")' && echo OKCODEX
rm -rf "$tmpd" "$ovr"
```
Expected: prints `true` then `OKCODEX`.

- [ ] **Step 7: Commit.** Message: `feat(hooks): make repo-start reminder hooks configurable`.

---

### Task B4: Make the Codex agent-subject prompt hook configurable

**Files:**
- Modify: `roles/common/files/bin/codex-remind-agent-subject-on-prompt`

**Interfaces:**
- Consumes: config / shared snippet (uses full ids). Verified by `tests/agent-subject-hooks.sh` (CODEX_HOOK), already updated in B2 to pin a default config.

- [ ] **Step 1: Edit the script.** Insert the shared snippet after line 2 (`set -euo pipefail`). Replace the literal match regex (line 10) with one built from the full ids:

```bash
match_re="(\\\$|^[[:space:]]*)(${NMB_BRAINSTORMING_SKILL}|${NMB_DEBUGGING_SKILL})([^[:alnum:]_-]|\$)"
if ! printf '%s\n' "$prompt" | grep -Eq "$match_re"; then
  exit 0
fi
```
And update the reminder text (line 18) to name the configured verbs:

```bash
reminder='You invoked '"$NMB_BRAINSTORMING_VERB"' or '"$NMB_DEBUGGING_VERB"' in a tmux agent pane without a current subject. Before continuing, run `tmux-agent-subject set "<short subject>"` using a concise noun phrase for this task.'
```

- [ ] **Step 2: Run the agent-subject suite, expect pass:**

```bash
bash tests/agent-subject-hooks.sh
```
Expected: all PASS (default config: still matches `$superpowers:systematic-debugging`, reminder contains `systematic-debugging`).

- [ ] **Step 3: Commit.** Message: `feat(hooks): make codex agent-subject hook configurable`.

---

### Task B5: Template the base CLAUDE.md fragment

**Files:**
- Create: `roles/common/templates/claude/CLAUDE.md.d/00-base.md.j2` (content = current `00-base.md` with the tmux-subject line templated)
- Delete: `roles/common/files/claude/CLAUDE.md.d/00-base.md`
- Modify: `roles/common/tasks/main.yml` ("Install base ~/.claude/CLAUDE.md fragment" task: `copy`→`template`)

- [ ] **Step 1: Create the template.** Copy the current `00-base.md` verbatim to `roles/common/templates/claude/CLAUDE.md.d/00-base.md.j2`, then change only the tmux-subject bullet to:

```markdown
* Tmux agent subject: when invoking `{{ brainstorming_skill }}` or `{{ debugging_skill }}` inside tmux, run `tmux-agent-subject set "<short subject>"` if the pane has no current subject or the previous subject is stale.
```

- [ ] **Step 2: Remove the old static fragment:**

```bash
git -C "$(git rev-parse --show-toplevel)" rm roles/common/files/claude/CLAUDE.md.d/00-base.md
```

- [ ] **Step 3: Switch the Ansible task** ("Install base ~/.claude/CLAUDE.md fragment", ~line 447) from `copy` to `template`:

```yaml
- name: Install base ~/.claude/CLAUDE.md fragment
  template:
    src: '{{ playbook_dir }}/roles/common/templates/claude/CLAUDE.md.d/00-base.md.j2'
    dest: '{{ ansible_facts["user_dir"] }}/.claude/CLAUDE.md.d/00-base.md'
    mode: '0600'
```

- [ ] **Step 4: Verify render (default).** Run:

```bash
ansible localhost -m template -a "src=roles/common/templates/claude/CLAUDE.md.d/00-base.md.j2 dest=/tmp/00-base-check.md" -e brainstorming_skill=superpowers:brainstorming -e debugging_skill=superpowers:systematic-debugging
grep -n 'superpowers:brainstorming.*superpowers:systematic-debugging' /tmp/00-base-check.md && rm /tmp/00-base-check.md
```
Expected: the tmux-subject line prints with both default ids.

- [ ] **Step 5: Commit.** Message: `feat(claude): template base CLAUDE.md fragment for pluggable skill ids`.

---

### Task B6: Make the `_recover-agent-sessions` cosmetic strip configurable

**Files:**
- Modify: `roles/common/files/bin/_recover-agent-sessions` (around line 370)

**Interfaces:**
- Consumes: `~/.claude/hooks/initiation-skills.sh` (parsed for the brainstorming verb), honoring `NMB_INITIATION_SKILLS_CONFIG` like the bash hooks.

- [ ] **Step 1: Add a small reader** near the top of the Ruby script (after other constants/helpers). It parses the simple `KEY='value'` config without sourcing shell:

```ruby
def brainstorming_verb
  cfg = ENV["NMB_INITIATION_SKILLS_CONFIG"] ||
        File.join(Dir.home, ".claude", "hooks", "initiation-skills.sh")
  id = "superpowers:brainstorming"
  if File.file?(cfg)
    File.foreach(cfg) do |line|
      if (m = line.match(/\ANMB_BRAINSTORMING_SKILL=['"]?([^'"\n]+)['"]?/))
        id = m[1]
        break
      end
    end
  end
  id.split(":").last
end
```

- [ ] **Step 2: Use it in `normalize_summary_candidate`** (replace the hardcoded `brainstorming` strip at line ~370):

```ruby
  verb = Regexp.escape(brainstorming_verb)
  if cleaned.match?(/\AUsing `?#{verb}`?\.\s*/i)
    cleaned = cleaned.sub(/\AUsing `?#{verb}`?\.\s*/i, "")
  end
```

- [ ] **Step 3: Manual verify both ways:**

```bash
ruby -e 'load "roles/common/files/bin/_recover-agent-sessions"' 2>/dev/null || true   # ensure it parses
# default
printf "Using \`brainstorming\`. did the thing" | NMB_INITIATION_SKILLS_CONFIG=/nonexistent ruby -e 'def brainstorming_verb; "brainstorming"; end' >/dev/null 2>&1
```
Pragmatic check: confirm the file still parses with `ruby -c roles/common/files/bin/_recover-agent-sessions` (Expected: `Syntax OK`). The strip is cosmetic; the syntax check plus a quick read of the diff is sufficient.

- [ ] **Step 4: Commit.** Message: `feat(recover): configurable brainstorming verb for summary strip`.

---

### Task C1: Full-surface integration verification

**Files:** none (verification only)

- [ ] **Step 1: Run every touched/added test:**

```bash
bash tests/agent-subject-hooks.sh
bash tests/block-initiation-skill.sh
bash roles/common/files/claude/hooks/remind-repo-start-on-dev-prompt.sh.test
bash tests/ci-test-inventory.sh
ruby -c roles/common/files/bin/_recover-agent-sessions
```
Expected: all PASS / `Syntax OK`.

- [ ] **Step 2: Provision dry-run, env unset (must be a no-op beyond the new default-valued config file).** From the worktree:

```bash
bin/provision --check --diff 2>&1 | tee /tmp/prov-default.log | grep -iE "changed:|CLAUDE.md|initiation-skills|plugin" | head -40
```
Expected: superpowers still in the plugin loop; `00-base.md` content unchanged (renders identical default ids); only the new `initiation-skills.sh` shows as a created file.

- [ ] **Step 3: Provision dry-run with overrides set** (proves the seam end-to-end without mutating the machine):

```bash
NMB_INSTALL_SUPERPOWERS_PLUGIN=false NMB_BRAINSTORMING_SKILL=alt:solution-design NMB_DEBUGGING_SKILL=alt:root-cause-debugging \
  bin/provision --check --diff 2>&1 | tee /tmp/prov-override.log | grep -iE "initiation-skills|00-base|plugin|alt:" | head -40
```
Expected: plugin loop omits superpowers; `initiation-skills.sh` + `00-base.md` diffs show `alt:solution-design`/`alt:root-cause-debugging`.

- [ ] **Step 4: Apply for real with defaults** (this machine should be unchanged behaviorally; writes the default config file):

```bash
bin/provision 2>&1 | tail -20
```
Expected: success; `~/.claude/hooks/initiation-skills.sh` now exists with superpowers defaults; assembled `~/.claude/CLAUDE.md` unchanged.

- [ ] **Step 5: Final commit if any cleanup**, then proceed to PR via the project's PR flow.

---

## Out of scope (separate, private follow-up)

The consumer wiring in a **private downstream provisioner** — exporting `NMB_INSTALL_SUPERPOWERS_PLUGIN=false` + the two skill-id overrides around its upstream `bin/provision` call, uninstalling the now-unmanaged superpowers plugin, adding its preferred marketplace, and installing the alternate skill plugin — is implemented under that repo's own private spec/plan/branch/PR after this lands. Do not add those concrete references here (public repo).

## Self-review notes

- Spec coverage: Part A → Task A1. Part B env vars/config → B1. CLAUDE.md → B5. case hooks → B2. repo-start reminders (Claude+Codex) → B3. codex agent-subject → B4. `_recover-agent-sessions` → B6. Testing + e2e → tests in B2/B3 + C1. Override channel (env→facts) → A1/B1.
- No placeholders; every code/edit step shows the content.
- Identifier consistency: `NMB_BRAINSTORMING_SKILL`/`NMB_DEBUGGING_SKILL` (full ids), `NMB_BRAINSTORMING_VERB`/`NMB_DEBUGGING_VERB` (post-colon), `NMB_INITIATION_SKILLS_CONFIG` (test override path), facts `install_superpowers_plugin`/`brainstorming_skill`/`debugging_skill` — used identically across tasks.
