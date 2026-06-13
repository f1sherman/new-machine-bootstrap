# murder Non-Interactive Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add explicit non-interactive confirmation bypass to `murder` while preserving the existing safe default prompt.

**Architecture:** Test the deployed Ruby template directly with real child processes. Implement `--yes`/`-y` as the explicit automation flag, keep `--force` as a compatibility alias, and make closed stdin fail before any signal is sent.

**Tech Stack:** Ruby CLI template, Ruby regression test, GitHub Actions workflow, Bash verification commands.

**Spec:** `docs/superpowers/specs/2026-06-13-murder-non-interactive-design.md`

---

## File Map

- `tests/murder.rb` - regression tests for non-interactive and closed-stdin behavior.
- `.github/workflows/integration-test.yml` - CI invocation for the new test file.
- `roles/macos/templates/murder` - Ruby CLI implementation.
- `docs/superpowers/specs/2026-06-13-murder-non-interactive-design.md` - approved design.
- `docs/superpowers/plans/2026-06-13-murder-non-interactive.md` - implementation record.

## Task 1: Add failing behavior tests

**Files:**
- Create: `tests/murder.rb`
- Modify: `.github/workflows/integration-test.yml`
- Test: `ruby tests/murder.rb`
- Test: `bash tests/ci-test-inventory.sh`

- [ ] **Step 1: Create the failing test**

Create `tests/murder.rb` with a small assertion harness. The test should spawn child Ruby processes that trap `TERM`, invoke `roles/macos/templates/murder` by PID, and assert:

- `--yes` works with stdin closed and does not print the prompt.
- `-y` works with stdin closed.
- no bypass flag with stdin closed exits non-zero and leaves the child alive.

- [ ] **Step 2: Add CI workflow invocation**

Add a workflow step after repo policy checks:

```yaml
      - name: Verify murder helper behavior
        run: ruby tests/murder.rb
```

- [ ] **Step 3: Verify red**

Run:

```bash
ruby tests/murder.rb
```

Expected: FAIL because `--yes` and `-y` are not yet accepted and closed stdin is not handled cleanly.

Run:

```bash
bash tests/ci-test-inventory.sh
```

Expected: PASS because the new test is referenced by CI.

## Task 2: Implement non-interactive mode

**Files:**
- Modify: `roles/macos/templates/murder`
- Test: `ruby tests/murder.rb`
- Test: `ruby -c roles/macos/templates/murder`

- [ ] **Step 1: Add parser state**

Rename the local `force` variable to `skip_confirmation`, default it to `false`, and pass it to `terminate_process`.

- [ ] **Step 2: Add `--yes` / `-y`**

Add an OptionParser entry:

```ruby
  parser.on('-y', '--yes', 'Run without confirmation prompt') do
    skip_confirmation = true
  end
```

Keep `--force` supported by setting the same variable.

- [ ] **Step 3: Handle closed stdin**

Update `confirm_kill` so it stores `response = STDIN.gets`, exits with a clear error when `response.nil?`, and only strips/downcases after the nil check.

- [ ] **Step 4: Verify green**

Run:

```bash
ruby tests/murder.rb
ruby -c roles/macos/templates/murder
```

Expected: all behavior tests pass and Ruby reports `Syntax OK`.

## Task 3: Final verification and PR

**Files:**
- Modify: docs plan checkboxes as work completes.
- Test: `bash tests/ci-test-inventory.sh`
- Test: `bash tests/repo-policy.sh all`

- [ ] **Step 1: Run full relevant verification**

Run:

```bash
ruby tests/murder.rb
ruby -c roles/macos/templates/murder
bash tests/ci-test-inventory.sh
bash tests/repo-policy.sh all
```

Expected: all commands exit 0.

- [ ] **Step 2: Commit changes**

Commit the spec, plan, tests, workflow, and implementation.

- [ ] **Step 3: Create pull request**

Push the branch and invoke the repo pull-request workflow.
