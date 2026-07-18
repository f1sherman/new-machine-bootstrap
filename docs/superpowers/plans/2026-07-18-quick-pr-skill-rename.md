# Quick PR Skill Rename Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the managed spec-to-PR workflow to quick PR across Claude, Codex, and Pi without changing workflow behavior.

**Architecture:** The shared Claude/Codex skill remains one directory copied to both runtimes, while Pi retains its generated-style `z-` counterpart. Existing lifecycle hooks and regression tests will recognize the new names only; Ansible cleanup will remove both pre-`z-` and immediately previous deployed names.

**Tech Stack:** Markdown skill definitions, Ruby contract tests, Bash hook tests, TypeScript Pi extension, Ansible YAML

## Global Constraints

- Claude and Codex expose `_quick-pr`; Pi exposes `z-quick-pr`.
- Preserve workflow behavior except for name-dependent text.
- Do not add aliases or permanent compatibility detection for the old names.
- Preserve historical specs and plans unchanged.
- Provisioning removes stale `_spec-to-pr`, `spec-to-pr`, and `z-spec-to-pr` deployed directories.

---

### Task 1: Rename the managed workflow and all active integrations

**Files:**
- Rename: `roles/common/files/config/skills/common/_spec-to-pr/` → `roles/common/files/config/skills/common/_quick-pr/`
- Rename: `roles/common/files/config/skills/pi/z-spec-to-pr/` → `roles/common/files/config/skills/pi/z-quick-pr/`
- Modify: `roles/common/files/config/skills/common/_quick-pr/SKILL.md`
- Modify: `roles/common/files/config/skills/pi/z-quick-pr/SKILL.md`
- Modify: `roles/common/files/pi/extensions/managed-hooks.ts`
- Modify: `roles/common/files/claude/hooks/block-initiation-skill-on-main.sh`
- Modify: `roles/common/files/claude/hooks/remind-repo-start-on-dev-prompt.sh`
- Modify: `roles/common/files/bin/codex-remind-repo-start-on-dev-prompt`
- Modify: `roles/common/tasks/main.yml`
- Test: `tests/pi-shared-skills.rb`
- Test: `tests/pi-managed-hooks.sh`
- Test: `roles/common/files/claude/hooks/remind-repo-start-on-dev-prompt.sh.test`

**Interfaces:**
- Consumes: managed skill directory names as runtime discovery identifiers; lifecycle prompts containing exact skill identifiers.
- Produces: `_quick-pr` for Claude/Codex, `z-quick-pr` for Pi, and explicit stale-name cleanup during provisioning.

- [ ] **Step 1: Update regression tests to require the new names**

In `tests/pi-shared-skills.rb`, replace the spec-to-PR-specific contract with:

```ruby
quick_pr_file = File.join(pi_root, "z-quick-pr", "SKILL.md")
quick_pr_contents = File.read(quick_pr_file)
abort "Pi z-quick-pr must return from writing-plans to z-quick-pr" unless quick_pr_contents.include?("return directly to `z-quick-pr`")
abort "Pi z-quick-pr must not return from writing-plans to old spec-to-pr names" if quick_pr_contents.match?(/return directly to `(?:z-)?spec-to-pr`/)

abort "Old common _spec-to-pr skill directory still exists" if Dir.exist?(File.join(skills_root, "common", "_spec-to-pr"))
abort "Old Pi z-spec-to-pr skill directory still exists" if Dir.exist?(File.join(pi_root, "z-spec-to-pr"))

%w[_spec-to-pr].each do |name|
  abort "Claude cleanup is missing #{name}" unless tasks_file.match?(/- name: Remove deleted managed Claude skills\n.*?^    - #{Regexp.escape(name)}$/m)
  abort "Codex cleanup is missing #{name}" unless tasks_file.match?(/- name: Remove deleted managed Codex skills\n.*?^    - #{Regexp.escape(name)}$/m)
end

%w[spec-to-pr z-spec-to-pr].each do |name|
  abort "Pi cleanup is missing #{name}" unless cleanup_block.match?(/^    - #{Regexp.escape(name)}$/)
end
```

In `tests/pi-managed-hooks.sh`, change the workflow array to:

```javascript
for (const workflow of ["z-fix", "z-spec-first", "z-quick-pr"]) {
```

In `roles/common/files/claude/hooks/remind-repo-start-on-dev-prompt.sh.test`, replace the old reminder case and add an explicit old-name rejection:

```bash
run_reminder_case "reminds for _quick-pr on main" "run _quick-pr on this idea" "main"
run_silent_case "silent for old _spec-to-pr on main" "run _spec-to-pr on this idea" "main"
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
ruby tests/pi-shared-skills.rb
bash tests/pi-managed-hooks.sh
bash roles/common/files/claude/hooks/remind-repo-start-on-dev-prompt.sh.test
```

Expected: all three fail because `z-quick-pr`/`_quick-pr` do not exist or the hooks still recognize only the old names.

- [ ] **Step 3: Rename the skill directories**

Run:

```bash
mv roles/common/files/config/skills/common/_spec-to-pr roles/common/files/config/skills/common/_quick-pr
mv roles/common/files/config/skills/pi/z-spec-to-pr roles/common/files/config/skills/pi/z-quick-pr
```

In `roles/common/files/config/skills/common/_quick-pr/SKILL.md`, make only these name-dependent replacements:

```markdown
name: _quick-pr
# Quick PR
> written and self-reviewed, return directly to `_quick-pr` so it can
```

In `roles/common/files/config/skills/pi/z-quick-pr/SKILL.md`, make the matching Pi replacements:

```markdown
name: z-quick-pr
# Quick PR
> written and self-reviewed, return directly to `z-quick-pr` so it can
```

Leave all other workflow instructions unchanged.

- [ ] **Step 4: Update active lifecycle integrations**

In `roles/common/files/pi/extensions/managed-hooks.ts`, use:

```typescript
const REPO_START_TRIGGERS = /(^|\s)(?:z-fix|z-spec-first|z-quick-pr|superpowers:systematic-debugging|superpowers:brainstorming)(?=\s|$)/i;
```

In `roles/common/files/claude/hooks/block-initiation-skill-on-main.sh`, use:

```bash
  superpowers:brainstorming|superpowers:systematic-debugging|_spec-first|_quick-pr|_fix) ;;
```

In both `roles/common/files/claude/hooks/remind-repo-start-on-dev-prompt.sh` and `roles/common/files/bin/codex-remind-repo-start-on-dev-prompt`, use:

```bash
skill_pattern='(^|[^[:alnum:]_])(_fix|_spec-first|_quick-pr|systematic-debugging|brainstorming)([^[:alnum:]_]|$)'
```

- [ ] **Step 5: Add explicit stale deployment cleanup**

In both `Remove deleted managed Claude skills` and `Remove deleted managed Codex skills` loops in `roles/common/tasks/main.yml`, add:

```yaml
    - _spec-to-pr
```

Keep the existing Pi cleanup entry:

```yaml
    - spec-to-pr
```

and add:

```yaml
    - z-spec-to-pr
```

Do not recognize old names in runtime hooks; cleanup is the only compatibility action.

- [ ] **Step 6: Run focused tests and verify GREEN**

Run:

```bash
ruby tests/pi-shared-skills.rb
bash tests/pi-managed-hooks.sh
bash roles/common/files/claude/hooks/remind-repo-start-on-dev-prompt.sh.test
```

Expected: all commands exit 0; Ruby prints the Pi shared-skill PASS line, Pi hooks print `pi-managed-hooks checks complete`, and every Claude hook case prints PASS.

- [ ] **Step 7: Verify active references and Ansible syntax**

Run:

```bash
rg -n '(_spec-to-pr|z-spec-to-pr)' roles tests \
  --glob '!roles/common/tasks/main.yml' \
  --glob '!tests/pi-shared-skills.rb' \
  --glob '!roles/common/files/claude/hooks/remind-repo-start-on-dev-prompt.sh.test'
ansible-playbook playbook.yml --syntax-check
```

Expected: `rg` exits 1 with no output; Ansible exits 0 and prints `playbook: playbook.yml`.

- [ ] **Step 8: Inspect the rename and commit**

Run:

```bash
git diff --check
git status --short
git diff --stat
git diff
```

Expected: only the two skill renames and listed active integration/test files are changed; skill bodies differ only in name-dependent text.

Invoke the repository-managed `z-commit` skill with all changed files and the imperative message:

```text
Rename spec-to-PR workflow to quick PR
```
