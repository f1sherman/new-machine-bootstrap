# Name-Only Agent Session Registry Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the registry `goal` field, publish only Pi session names, and release and provision agent-session-registry `v0.2.0`.

**Architecture:** The public Ruby repository owns a schema version 2 migration that rebuilds the sessions table without `goal`. NMB waits for PR #441, merges updated `main` into PR #443 without rewriting published history, and publishes the built-in Pi session name through the existing serialized nonblocking registry queue.

**Tech Stack:** Ruby 4.0, SQLite3, Minitest, TypeScript Pi extensions, Bash test harness, Ansible, GitHub Actions.

## Global Constraints

- NMB PR #441 must merge before NMB hook implementation begins.
- Public release version and Git tag are `0.2.0` and `v0.2.0`.
- Existing `name` values remain unchanged during migration.
- Existing `goal` values are discarded and never copied into `name`.
- The registry schema, CLI, JSON, and human output contain no `goal` field.
- Registry publication remains serialized, nonblocking, and failure-isolated.
- Only persistent Pi sessions with both a session ID and session file register.
- Shutdown never marks a session done.
- `z-session-done` remains the explicit completion path.
- Use public-repository and NMB pull requests. Do not force-push or move published tags.

---

## File Structure

### Public `f1sherman/agent-session-registry`

- `VERSION`: public version `0.2.0`.
- `lib/agent_session_registry/record.rb`: fixed name-only record fields.
- `lib/agent_session_registry/database.rb`: schema version 2 and version 1 migration.
- `lib/agent_session_registry/cli.rb`: name-only register, update, and output behavior.
- `test/database_test.rb`: migration, rollback, schema, and persistence tests.
- `test/cli_test.rb`: removed-option and name-only output tests.
- `README.md`: name-only command and record documentation.

### NMB

- `roles/common/files/pi/extensions/managed-hooks.ts`: name-only registry registration and updates on top of PR #441.
- `tests/pi-managed-hooks.sh`: name-only publication, ordering, failure, and persistence-gate tests.
- `vars/tool_versions.yml`: immutable `v0.2.0` pin.
- `docs/superpowers/specs/2026-08-09-agent-session-registry-name-only-design.md`: approved design.
- `docs/superpowers/plans/2026-08-09-agent-session-registry-name-only.md`: this plan.

---

### Task 1: Wait for and Integrate NMB PR #441

**Files:**
- No file changes before the gate passes.
- Merge updated `main` later in the existing PR #443 worktree.

**Interfaces:**
- Consumes: merged NMB PR #441 name-only `managed-hooks.ts` and test harness.
- Produces: a conflict-free base for Task 3.

- [x] **Step 1: Check PR #441**

Run:

```bash
gh pr view 441 -R f1sherman/new-machine-bootstrap \
  --json state,mergeCommit,statusCheckRollup
```

Expected: `state` is `MERGED` and the `provision` check succeeded. If it is still open, stop execution without changing either repository.

- [x] **Step 2: Update the NMB feature branch**

After #441 merges, run from the PR #443 worktree:

```bash
git fetch origin main
git merge --no-edit origin/main
```

Resolve `managed-hooks.ts` and `tests/pi-managed-hooks.sh` by keeping #441's name-only identity model. Preserve the existing registry adapter, completion skill, provisioning, and public-repository pin for later tasks. Do not restore `currentSessionGoal`, custom `session-goal` entries, or separate goal publication.

- [x] **Step 3: Verify the merged baseline**

Run:

```bash
bash tests/pi-managed-hooks.sh
git diff --check origin/main...HEAD
```

Expected: existing name-only managed-hook tests pass before Task 3 adds registry changes.

---

### Task 2: Release the Name-Only Public Registry

**Files:**
- Modify: `tmp/agent-session-registry/VERSION`
- Modify: `tmp/agent-session-registry/lib/agent_session_registry/record.rb`
- Modify: `tmp/agent-session-registry/lib/agent_session_registry/database.rb`
- Modify: `tmp/agent-session-registry/lib/agent_session_registry/cli.rb`
- Modify: `tmp/agent-session-registry/test/database_test.rb`
- Modify: `tmp/agent-session-registry/test/cli_test.rb`
- Modify: `tmp/agent-session-registry/README.md`

**Interfaces:**
- Produces: `AgentSessionRegistry::Database::SCHEMA_VERSION == 2`.
- Produces: `Record::FIELDS` without `goal`.
- Preserves: `asr list|show|register|update|done|resume` and adapter protocol.
- Produces: public Git tag `v0.2.0` for Task 3.

- [ ] **Step 1: Create a public feature branch**

From the public repository main checkout:

```bash
git fetch origin main
git switch main
git pull --ff-only origin main
git worktree add .worktrees/remove-goal -b feat/remove-goal
```

Expected: the new worktree starts at public `main` version `0.1.1`.

- [ ] **Step 2: Write failing schema and migration tests**

Update `test/database_test.rb` to assert:

```ruby
assert_equal 2, connection.get_first_value("PRAGMA user_version")
refute_includes table_columns(connection, "sessions"), "goal"
assert_equal %i[
  source hostname session_id remote status name cwd adapter adapter_config
  created_at updated_at
], AgentSessionRegistry::Record::FIELDS
```

Create a real version 1 database with the old table shape and a row whose `name` is empty and `goal` is non-empty. Open it with `Database.new`, then assert version 2, unchanged empty `name`, preserved retained fields, and no `goal` column.

Create a malformed version 1 table that makes the copy fail. Assert `Database.new` raises, `PRAGMA user_version` remains 1, and the original `sessions` table and `goal` column remain. Change the newer-schema rejection fixture from version 2 to version 3.

- [ ] **Step 3: Write failing CLI tests**

Update `test/cli_test.rb` so production `bin/asr` output and JSON have no `goal`. Add subprocess assertions:

```ruby
status, _stdout, stderr = run_asr("register", *valid_registration, "--goal", "old")
assert_equal 2, status.exitstatus
assert_match(/invalid option: --goal/, stderr)

status, _stdout, stderr = run_asr("update", key, "--goal", "old")
assert_equal 2, status.exitstatus
assert_match(/invalid option: --goal/, stderr)
```

Remove goal-specific layout branches. Keep exact full human-record output assertions with `name` followed by `cwd`.

- [ ] **Step 4: Confirm the focused red state**

Run:

```bash
bundle exec ruby -Ilib:test test/database_test.rb
bundle exec ruby -Ilib:test test/cli_test.rb
```

Expected: failures show schema version 1, the existing `goal` column/options, or old output.

- [ ] **Step 5: Implement schema version 2**

In `database.rb`:

```ruby
SCHEMA_VERSION = 2
MUTABLE_FIELDS = %i[remote status name cwd adapter adapter_config].freeze
```

Remove `goal` from `CREATE_SESSIONS` and registration normalization. Split migration by version:

```ruby
case version
when 0
  database.execute_batch(CREATE_SESSIONS)
when 1
  database.execute_batch(<<~SQL)
    ALTER TABLE sessions RENAME TO sessions_v1;
    #{CREATE_SESSIONS}
    INSERT INTO sessions (
      source, hostname, session_id, remote, status, name, cwd, adapter,
      adapter_config, created_at, updated_at
    )
    SELECT
      source, hostname, session_id, remote, status, name, cwd, adapter,
      adapter_config, created_at, updated_at
    FROM sessions_v1;
    DROP TABLE sessions_v1;
  SQL
end
database.execute("PRAGMA user_version = 2")
```

Keep this inside the existing `BEGIN IMMEDIATE` transaction. Do not use `DROP COLUMN` or copy `goal` into `name`.

- [ ] **Step 6: Remove goal from records and CLI**

Set `Record::FIELDS` to the exact name-only list from Step 2. Remove `--goal` option handlers, registration values, update changes, and human rendering from `cli.rb`. Unknown `--goal` must continue through OptionParser's concise exit-2 error path.

- [ ] **Step 7: Update version and documentation**

Set `VERSION` to `0.2.0`. Update every README command, field list, JSON example, and output example to use `name` only. A repository search must find no public contract reference to a goal field:

```bash
rg -n '\bgoal\b|--goal' README.md lib test
```

Expected: only migration fixtures or assertions about rejecting the removed option remain.

- [ ] **Step 8: Run public verification**

Run:

```bash
bundle exec rake test
ruby -c lib/agent_session_registry/database.rb
ruby -c lib/agent_session_registry/cli.rb
git diff --check
```

Expected: all tests and syntax checks pass.

- [ ] **Step 9: Commit, review, and open the public PR**

Commit the public files with an imperative message such as:

```text
Remove the session goal field
```

Run an independent review focused on migration rollback, exact retained data, removed CLI surface, and unchanged resume safety. Push and open a public PR with base `main`.

- [ ] **Step 10: Merge and tag v0.2.0**

After public CI passes and review is clean, merge the public PR. Update local public `main`, then run:

```bash
git tag -a v0.2.0 -m "Release v0.2.0"
git push origin v0.2.0
git describe --tags --exact-match
```

Expected: `v0.2.0`. Never move `v0.1.0` or `v0.1.1`.

---

### Task 3: Adapt NMB Registry Publication to Names

**Files:**
- Modify: `roles/common/files/pi/extensions/managed-hooks.ts`
- Modify: `tests/pi-managed-hooks.sh`
- Modify: `vars/tool_versions.yml`

**Interfaces:**
- Consumes: PR #441's built-in Pi session name lifecycle.
- Consumes: public `v0.2.0` CLI without `--goal`.
- Produces: serialized `asr register ... --name <name>` and `asr update ... --name <name>`.

- [ ] **Step 1: Write failing name-only registry tests**

In the merged `tests/pi-managed-hooks.sh`, add deferred `asr` responses and assert:

- persistent `session_start` registers source `pi`, native ID, local mode, active status, built-in name, cwd, adapter, and session-file config;
- registration arguments do not contain `--goal`;
- empty session ID or session file skips registration;
- `session_info_changed` queues `update --source pi --session-id <id> --name <name>`;
- two deferred names publish in order and the newest name is last;
- slow registry work does not delay session start or name synchronization;
- nonzero and thrown registry failures do not reject lifecycle handlers;
- `session_tree` produces no separate goal update;
- shutdown never calls `asr done`.

- [ ] **Step 2: Confirm the focused red state**

Run:

```bash
bash tests/pi-managed-hooks.sh
```

Expected: registry assertions fail because the conflict resolution keeps #441's hook behavior without the old goal-based registry integration.

- [ ] **Step 3: Reapply the serialized registry boundary**

Inside the extension factory, add:

```typescript
let registryPublicationChain = Promise.resolve();

function serializeRegistryPublication(operation) {
  const result = registryPublicationChain.then(operation);
  registryPublicationChain = result.catch(() => {});
  return result;
}
```

Keep `registrySession`, `runRegistryCommand`, registration, and name update helpers. Registration arguments are exactly:

```text
register --source pi --session-id <id> --local --status active
--name <name> --cwd <cwd> --adapter pi-local
--adapter-config {"session_file":"<absolute path>"}
```

Name update arguments are exactly:

```text
update --source pi --session-id <id> --name <name>
```

Every value remains a separate `pi.exec` argument. Do not build a shell command.

- [ ] **Step 4: Wire the name-only lifecycle**

Queue registration from `session_start` after #441 resets its lifecycle. Queue name updates from `session_info_changed` using the event name. Keep both calls fire-and-forget so registry latency does not block Pi.

Do not add registry calls to `applySessionName`, `session_tree`, or `session_shutdown`. #441 routes automatic and explicit naming through `session_info_changed`, which is the single registry update point.

- [ ] **Step 5: Pin the public release**

Change only the existing value:

```yaml
# renovate: datasource=github-tags depName=f1sherman/agent-session-registry
agent_session_registry: v0.2.0
```

- [ ] **Step 6: Run NMB verification**

Run:

```bash
bash tests/pi-managed-hooks.sh
ruby tests/pi-session-registry-adapter.rb
bash tests/tmux-agent-state.sh
ansible-playbook playbook.yml --syntax-check
git diff --check origin/main...HEAD
```

Expected: all checks pass.

- [ ] **Step 7: Commit and review**

Commit the hook, harness, and version pin. Run an independent review focused on name-event coverage, queue ordering, stale-context safety inherited from #441, nonblocking behavior, and absence of goal arguments.

---

### Task 4: Provision, Verify, and Update NMB PR #443

**Files:**
- Verify the full NMB branch.
- Do not edit deployed files directly.

**Interfaces:**
- Consumes: public `v0.2.0` and name-only NMB integration.
- Produces: deployed name-only registry and updated NMB PR #443.

- [ ] **Step 1: Provision from the feature worktree**

Run:

```bash
bin/provision
```

Expected: zero failed tasks. Confirm the newest provision log names the PR #443 worktree, branch, clean commit, and no arguments.

- [ ] **Step 2: Verify the deployed release**

Run:

```bash
git -C ~/.local/share/agent-session-registry describe --tags --exact-match
~/.local/bin/asr --help
test -x ~/.local/lib/agent-session-registry/adapters/pi-local
```

Expected: tag `v0.2.0`, working help, and executable adapter.

- [ ] **Step 3: Run a live name-only Pi cycle**

Start an isolated persistent Pi session with a known native session ID and name. Verify `asr show <key> --json` contains `name` and no `goal`, plus correct hostname, cwd, adapter, and absolute session file.

Change the Pi session name and verify the same record updates. Mark only that isolated session done with the exact `z-session-done` command contract. Resume it through `asr resume <key>`, exit, and verify resume returns it to `active` while ordinary shutdown leaves it `active`.

- [ ] **Step 4: Run final checks**

Run:

```bash
cd tmp/agent-session-registry && bundle exec rake test
cd ../..
ruby tests/pi-session-registry-adapter.rb
bash tests/pi-managed-hooks.sh
bash tests/tmux-agent-state.sh
ansible-playbook playbook.yml --syntax-check
git diff --check origin/main...HEAD
```

Expected: all checks pass.

- [ ] **Step 5: Update PR #443**

Push the merged branch normally. Verify the remote head matches local `HEAD`. Update the PR title/body because its name-and-goal wording is stale. Reply to any superseded goal-specific review thread with the new name-only behavior.

Rearm the PR monitor for:

```text
repo: /Users/brian/projects/new-machine-bootstrap/.worktrees/feat-pi-session-registry
head: feat/pi-session-registry
base: main
PR: 443
```

Expected: PR #443 CI starts on the final name-only branch.
