# Streamline NMB Tests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply NMB's strict test-value gate, remove low-value coverage, trim mixed suites, and make the repository-local policy govern future pull requests.

**Architecture:** Keep the existing provisioning-first GitHub Actions job and its standalone behavioral tests. Remove tests that fail any approved gate. Reduce mixed tests to the cases that protect material runtime risks, and document the gate in the repository-local agent instructions.

**Tech Stack:** Ansible, Bash, Ruby/Minitest, GitHub Actions YAML, repository-local Markdown guidance.

## Global Constraints

- The policy applies only to `new-machine-bootstrap`.
- A test must pass all four gates: material harm, complex behavior, behavioral verification, and unique protection.
- Do not change managed global guidance under `roles/common/files/` or shared skills.
- Do not add a test runner, coverage target, or policy-enforcement test.
- Keep provisioning verification intact.
- Use manual or end-to-end verification when no valuable automated test exists.

---

### Task 1: Add the repository-local test policy

**Files:**
- Modify: `CLAUDE.md` under `## Agent Behavior`
- Indirect interface: `AGENTS.md` is a symlink to `CLAUDE.md`

**Interfaces:**
- Consumes: the four gates from `docs/superpowers/specs/2026-08-06-test-value-policy-design.md`
- Produces: repository-local instructions loaded through either `CLAUDE.md` or `AGENTS.md`

- [ ] **Step 1: Add one concise local guidance item**

Add an `Agent Behavior` bullet that requires all four gates, rejects static
configuration and bookkeeping tests, permits manual or end-to-end verification,
and states that no test is better than a low-value test.

- [ ] **Step 2: Verify the scope and symlink**

Run:

```bash
test "$(readlink AGENTS.md)" = CLAUDE.md
rg -n "Material harm|Complex behavior|Behavioral verification|Unique protection" \
  CLAUDE.md
git diff -- roles/common/files/pi roles/common/files/claude \
  roles/common/files/config/skills
```

Expected: the four gate names are present in `CLAUDE.md`; the managed global
paths have no diff.

- [ ] **Step 3: Commit**

```bash
~/.pi/agent/skills/z-commit/commit.sh \
  -m "Require material value from NMB tests" \
  CLAUDE.md
```

### Task 2: Remove tests that fail the gate

**Files:**
- Delete:
  - `tests/agent-spec-directory.sh`
  - `tests/agent-subject-hooks.sh`
  - `tests/ci-test-inventory.sh`
  - `tests/dev-host-claude-permissions.sh`
  - `tests/editor-env-contract.sh`
  - `tests/ghostty-quick-terminal.sh`
  - `tests/git-credential-helper-contract.sh`
  - `tests/git-init-template-contract.sh`
  - `tests/gsd-browser-package-contract.rb`
  - `tests/managed-mise-npm-install-contract.rb`
  - `tests/mise-ruby-install-contract.rb`
  - `tests/paranoid-package-tools.rb`
  - `tests/pi-agent-assemble-agents.sh`
  - `tests/pi-attention-bell.sh`
  - `tests/pi-managed-aube-update-contract.rb`
  - `tests/pi-scheduled-subagent-runs.sh`
  - `tests/pi-shared-skills.rb`
  - `tests/pi-skill-conflicts.rb`
  - `tests/pi-spec-shortcut.sh`
  - `tests/pinned-github-binary-privilege-boundary.sh`
  - `tests/provision-mise-github-token.sh`
  - `tests/rectangle-migration-contract.rb`
  - `tests/repo-tests-tmux-isolation.sh`
  - `tests/retired-coding-agent-references.sh`
  - `tests/tmux-agent-key-passthrough.sh`
  - `tests/tmux-agent-state-completed-subject.sh`
  - `tests/tmux-edge-suffix.sh`
  - `tests/tmux-label-helper-provisioning.sh`
  - `tests/tmux-managed-bars-contract.sh`
  - `tests/tmux-pane-title-changed.rb`
  - `tests/tmux-spec-current.rb`
  - `tests/zsh-terminal-focus-reset.sh`
  - `roles/common/files/claude/hooks/remind-repo-start-on-dev-prompt.sh.test`
- Modify: `.github/workflows/integration-test.yml`

**Interfaces:**
- Consumes: the existing explicit workflow step list
- Produces: a workflow with no reference to a removed test and no low-value inline configuration assertions

- [ ] **Step 1: Delete the 33 rejected test files**

Use `git rm` with the exact paths above. These files fail at least one mandatory
gate. Most restate configuration, preserve completed migrations, protect cosmetic
preferences, test other tests, or duplicate broader retained behavior.

- [ ] **Step 2: Remove their workflow steps**

Delete the corresponding named steps from `.github/workflows/integration-test.yml`.
Also remove the final inline version, Zsh syntax, and dotfile-presence checks.
They restate installed configuration and fail the material-harm and unique-
protection gates. Keep the `Run provisioning` step unchanged.

- [ ] **Step 3: Verify workflow references**

Run:

```bash
yq -e '.' .github/workflows/integration-test.yml >/dev/null
while IFS= read -r path; do
  test -e "$path" || {
    printf 'missing workflow test: %s\n' "$path" >&2
    exit 1
  }
done < <(
  yq -r '.jobs.*.steps[]?.run // ""' .github/workflows/integration-test.yml |
    rg -o '(tests/[^[:space:]]+|roles/[^[:space:]]+[.]test)' |
    tr -d "'\""
)
```

Expected: valid YAML and no missing referenced test.

- [ ] **Step 4: Commit**

Commit the deletions and workflow changes as one coherent removal commit with:

```bash
~/.pi/agent/skills/z-commit/commit.sh \
  -m "Remove low-value NMB tests" \
  .github/workflows/integration-test.yml \
  tests \
  roles/common/files/claude/hooks/remind-repo-start-on-dev-prompt.sh.test
```

### Task 3: Trim mixed tests to material behavioral coverage

**Files:**
- Modify:
  - `tests/agent-current-spec-hook.rb`
  - `tests/claude-agent-subject-hook-settings.sh`
  - `tests/codex-bind-tmux-pane.sh`
  - `tests/codex-hook-trust.sh`
  - `tests/ghostty-session-manifest.rb`
  - `tests/gitignore-contract.sh`
  - `tests/pi-aube-install-layout-contract.rb`
  - `tests/pi-main-worktree-guard-provisioning.sh`
  - `tests/pi-managed-hooks.sh`
  - `tests/provision-concurrency-lock.sh`
  - `tests/provision-log-provenance.sh`
  - `tests/repo-lifecycle.sh`
  - `tests/tmux-agent-state.sh`
  - `tests/tmux-claude-session-start.sh`
  - `tests/tmux-label-contract.sh`
  - `tests/tmux-pane-link.sh`
  - `tests/tmux-restore-diagnostics.sh`
  - `tests/tmux-restore-startup.rb`
  - `tests/tmux-resurrect-nvim-space-path.sh`

**Interfaces:**
- Consumes: production scripts and helpers already invoked by each suite
- Produces: focused tests that check only material, complex, observable, unique behavior

- [ ] **Step 1: Remove static contracts from mixed suites**

Remove assertions that grep Ansible, workflow, template, prompt, registration,
exact wording, exact package declarations, exact source order, or task names.
Remove completed migration assertions and ordinary cosmetic formatting cases.
Do not replace them.

- [ ] **Step 2: Retain only the qualifying behavior by risk group**

Retain these behavioral boundaries:

- Cross-repository/worktree path selection in `agent-current-spec-hook.rb`.
- Preservation of unrelated user hooks in
  `claude-agent-subject-hook-settings.sh`.
- Exact-pane resume metadata in `codex-bind-tmux-pane.sh`.
- Trust, escaping, deduplication, user-state preservation, and drift recovery in
  `codex-hook-trust.sh`.
- Manifest integrity, locking, concurrent writes, and last-good-state
  preservation in `ghostty-session-manifest.rb`.
- Runtime-state exclusion without hiding real project configuration in
  `gitignore-contract.sh`.
- Pi executable resolution across supported layouts and malformed manifests in
  `pi-aube-install-layout-contract.rb`.
- Existing-user-state preservation and idempotent JSON merge behavior in
  `pi-main-worktree-guard-provisioning.sh`.
- Destructive Git parsing plus asynchronous ownership and persistence races in
  `pi-managed-hooks.sh`.
- Lock ownership, waiting, stale recovery, signals, successor races, and release
  in `provision-concurrency-lock.sh`.
- Secret redaction only in `provision-log-provenance.sh`.
- Branch-base selection, data-deletion guards, merge proof, dirty-state safety,
  pruning decisions, and interrupted recovery in `repo-lifecycle.sh`.
- Cross-process ownership and fail-closed state changes in
  `tmux-agent-state.sh`.
- Nested-session isolation and resume binding in
  `tmux-claude-session-start.sh`.
- Cross-session publication prevention plus lock, stale-worker, PID-reuse, and
  ownership races in `tmux-label-contract.sh`.
- Hostile URL input and tmux-format escaping in `tmux-pane-link.sh`.
- Restore exit-status preservation and diagnostics fail-open behavior in
  `tmux-restore-diagnostics.sh`.
- Concurrent reservation, abandoned recovery, failure cleanup, and safe-snapshot
  fallback in `tmux-restore-startup.rb`.
- Ambiguous Neovim path and command reconstruction in
  `tmux-resurrect-nvim-space-path.sh`.

- [ ] **Step 3: Run every trimmed suite**

Run each modified file with its existing interpreter. Expected: every command
exits zero. Do not weaken production behavior to make a test pass.

- [ ] **Step 4: Commit**

```bash
~/.pi/agent/skills/z-commit/commit.sh \
  -m "Focus NMB tests on material regressions" \
  tests
```

### Task 4: Verify the retained suite and quantify the reduction

**Files:**
- Verify: `.github/workflows/integration-test.yml`
- Verify: all remaining `tests/*`
- Verify: `CLAUDE.md` and `AGENTS.md`

**Interfaces:**
- Consumes: the final workflow and retained test inventory
- Produces: empirical pass results and before/after reduction metrics for the pull request

- [ ] **Step 1: Run syntax checks**

```bash
yq -e '.' .github/workflows/integration-test.yml >/dev/null
find tests -maxdepth 1 -type f -name '*.sh' -print0 |
  xargs -0 -n1 bash -n
find tests -maxdepth 1 -type f -name '*.rb' -print0 |
  xargs -0 -n1 ruby -c
```

Expected: all commands exit zero.

- [ ] **Step 2: Run all retained tests**

Execute every test referenced by `.github/workflows/integration-test.yml` in
workflow order. Record platform-specific skips as residual risks instead of
adding replacement contract tests.

- [ ] **Step 3: Provision and check idempotence**

```bash
bin/provision
bin/provision --check
```

Expected: provisioning succeeds. Check mode reports no unintended changes.

- [ ] **Step 4: Calculate objective reduction metrics**

Compare the branch with `main`:

```bash
hook=roles/common/files/claude/hooks/remind-repo-start-on-dev-prompt.sh.test
printf 'before_files='
{
  git ls-tree -r --name-only main tests
  git cat-file -e "main:$hook" 2>/dev/null && printf '%s\n' "$hook"
} | awk 'NF { count++ } END { print count + 0 }'
printf 'after_files='
{
  find tests -maxdepth 1 -type f -print
  test ! -f "$hook" || printf '%s\n' "$hook"
} | awk 'NF { count++ } END { print count + 0 }'
printf 'before_lines='
{
  git ls-tree -r --name-only main tests |
    while IFS= read -r path; do git show "main:$path"; done
  git cat-file -e "main:$hook" 2>/dev/null && git show "main:$hook"
} | awk 'END { print NR }'
printf 'after_lines='
{
  find tests -maxdepth 1 -type f -print0 |
    while IFS= read -r -d '' path; do cat "$path"; done
  test ! -f "$hook" || cat "$hook"
} | awk 'END { print NR }'
```

Report file removal, test-code line removal, and the latest available CI duration.
Distinguish test reduction from the unchanged provisioning duration.

- [ ] **Step 5: Review the final diff**

Confirm:

- no production script, task, or template behavior was removed;
- no global guidance or shared skill changed;
- each remaining test has a material-risk justification from Task 3 or is one of
  the 13 unchanged qualifying suites;
- every workflow test reference exists.

- [ ] **Step 6: Commit any verification-only correction**

If verification required a correction, commit only that correction with an
imperative message. If no tracked files changed, do not create an empty commit.
