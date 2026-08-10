# Agent Session Registry Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and publish the MIT-licensed `f1sherman/agent-session-registry` Ruby CLI, then provision it through NMB with automatic Pi session publication, a Pi resume adapter, and the explicit `z-session-done` skill.

**Architecture:** The public repository owns the agent-neutral Ruby CLI, SQLite schema, and action-based external adapter dispatcher. NMB pins the public Git tag, installs the runtime and Pi adapter, and extends its existing managed Pi hook to publish persistent session identity without making registry failures block Pi.

**Tech Stack:** Ruby 4.0.2, `sqlite3`, Minitest, SQLite WAL, Ansible, TypeScript Pi extensions, Bash/Ruby adapter integration tests, GitHub CLI.

## Global Constraints

- The public repository is `f1sherman/agent-session-registry` and uses the MIT License.
- The only executable name is `asr`.
- The initial public version and Git tag are `0.1.0` and `v0.1.0`.
- The registry has no daemon, web service, browser view, or network listener.
- The composite identity is `(source, hostname, session_id)`.
- The only statuses are `active` and `done`.
- Session completion occurs only after an explicit user request.
- Session records contain no arbitrary metadata and no arbitrary commands.
- External adapters live under `~/.local/lib/agent-session-registry/adapters/`.
- Adapter invocation is `<adapter> <action> <registry-key> <adapter-config-json>` without a shell.
- Version 1 defines only the adapter action `resume`.
- NMB must not register ephemeral Pi sessions or infer completion from shutdown.
- NMB repository changes must remain in the existing feature worktree.
- Stage the new public repository only under the NMB worktree's ignored `tmp/` directory; do not modify deployed files directly.
- Before publishing the public repository, show the complete proposed content and get the required explicit publication authorization.

---

## File Structure

### Public `f1sherman/agent-session-registry` repository

- `LICENSE`: standard MIT License.
- `README.md`: installation, commands, schema, environment overrides, and adapter-author contract.
- `Gemfile`: runtime/test dependency on `sqlite3`.
- `Rakefile`: default Minitest task.
- `VERSION`: literal `0.1.0`.
- `bin/asr`: thin executable that loads `AgentSessionRegistry::CLI`.
- `lib/agent_session_registry/identity.rb`: identity validation, hostname normalization, and rendered-key parsing.
- `lib/agent_session_registry/record.rb`: fixed record fields and JSON serialization.
- `lib/agent_session_registry/database.rb`: schema creation, migrations, transactions, CRUD, filters, and timestamps.
- `lib/agent_session_registry/adapter.rb`: safe adapter resolution, spawn, and wait operations.
- `lib/agent_session_registry/cli.rb`: OptionParser commands, output formatting, and error-to-exit behavior.
- `test/test_helper.rb`: temporary paths, subprocess helpers, and fixed fixtures.
- `test/database_test.rb`: schema, persistence, idempotence, filters, and concurrency.
- `test/adapter_test.rb`: action protocol and safe executable resolution.
- `test/cli_test.rb`: production `bin/asr` command behavior and human/JSON output.

### NMB repository

- `vars/tool_versions.yml`: pinned `v0.1.0` Git tag.
- `roles/common/tasks/main.yml`: clone, dependency, executable link, adapter directory, and adapter installation.
- `roles/common/files/agent-session-registry/adapters/pi-local`: Pi-specific action adapter.
- `roles/common/files/pi/extensions/managed-hooks.ts`: serialized register/name/goal publication.
- `roles/common/files/config/skills/pi/z-session-done/SKILL.md`: explicit current-session completion flow.
- `tests/pi-session-registry-adapter.rb`: production adapter behavioral test.
- `tests/pi-managed-hooks.sh`: Pi publication lifecycle tests.
- `.github/workflows/integration-test.yml`: run the material NMB adapter test.

---

### Task 1: Build Public Identity and SQLite Persistence

**Files:**
- Create in staged public repository: `LICENSE`
- Create in staged public repository: `Gemfile`
- Create in staged public repository: `Rakefile`
- Create in staged public repository: `VERSION`
- Create in staged public repository: `lib/agent_session_registry/identity.rb`
- Create in staged public repository: `lib/agent_session_registry/record.rb`
- Create in staged public repository: `lib/agent_session_registry/database.rb`
- Create in staged public repository: `test/test_helper.rb`
- Create in staged public repository: `test/database_test.rb`

**Interfaces:**
- Produces: `AgentSessionRegistry::Identity.parse(key)`, `.local(source:, session_id:)`, `.new(source:, hostname:, session_id:)`, and `#key`.
- Produces: `AgentSessionRegistry::Record::FIELDS` and `#to_h`.
- Produces: `AgentSessionRegistry::Database.new(path:, clock: -> { Time.now.utc })`.
- Produces database methods `register(attributes)`, `update(identity, changes)`, `done(identity)`, `fetch(identity)`, and `list(status: "active", remote: nil)`.
- Consumers in later tasks rely on `register`, `update`, and `done` returning a record hash with symbol keys.

- [ ] **Step 1: Create the isolated staged repository**

Run from the NMB feature worktree:

```bash
mkdir -p tmp/agent-session-registry
git -C tmp/agent-session-registry init -b main
```

Set local commit identity only if the new repository does not inherit it. Do not create files outside the NMB worktree.

- [ ] **Step 2: Write database tests before production code**

Create tests that assert these exact behaviors:

```ruby
identity = AgentSessionRegistry::Identity.new(
  source: "PI",
  hostname: "Build.EXAMPLE.",
  session_id: "019fe7a6-a219-7548-a6ef-1f23885864f4"
)
assert_equal "pi:build.example:019fe7a6-a219-7548-a6ef-1f23885864f4", identity.key
assert_equal identity, AgentSessionRegistry::Identity.parse(identity.key)
```

Use a temporary database and a controllable clock:

```ruby
record = database.register(
  source: "pi",
  hostname: "workstation",
  session_id: "session-1",
  remote: false,
  status: "active",
  name: "Registry work",
  goal: "Build session registry",
  cwd: "/work/repo",
  adapter: "pi-local",
  adapter_config: { "session_file" => "/sessions/one.jsonl" }
)
assert_equal "active", record.fetch(:status)
assert_equal "2026-08-09T12:00:00.000000Z", record.fetch(:created_at)
```

Cover in the same test file:

- schema `user_version` becomes `1`;
- a database with `user_version = 2` fails before mutation;
- register sets every fixed column;
- equivalent register does not change either timestamp;
- changed register preserves `created_at` and advances `updated_at`;
- update changes only supplied mutable fields;
- done changes only status and `updated_at`;
- repeated done does not change `updated_at`;
- list defaults to active and orders newest first;
- remote filter accepts true or false;
- invalid source, hostname, session ID, status, adapter, or non-object adapter config fails;
- two child processes can register different records concurrently without lock errors.

- [ ] **Step 3: Run tests and confirm the intended red state**

Run:

```bash
cd tmp/agent-session-registry
ruby -Ilib:test test/database_test.rb
```

Expected: failure because the `AgentSessionRegistry` implementation does not exist.

- [ ] **Step 4: Implement identity and record types**

Use these validation rules:

```ruby
NAME_PATTERN = /\A[a-z0-9][a-z0-9._-]*\z/
SESSION_ID_PATTERN = /\A[A-Za-z0-9][A-Za-z0-9._-]*\z/

def normalize_name(value)
  value.to_s.downcase.sub(/\.\z/, "")
end
```

`Identity.local` must call `Socket.gethostname`. `Identity.parse` must require exactly three colon-separated fields. Reject empty or invalid values with `ArgumentError`. Make identities immutable and value-comparable.

`Record::FIELDS` must be exactly:

```ruby
%i[
  source hostname session_id remote status name goal cwd adapter adapter_config
  created_at updated_at
].freeze
```

- [ ] **Step 5: Implement the SQLite schema and transactions**

Create this version 1 table shape:

```sql
CREATE TABLE sessions (
  source TEXT NOT NULL,
  hostname TEXT NOT NULL,
  session_id TEXT NOT NULL,
  remote INTEGER NOT NULL CHECK (remote IN (0, 1)),
  status TEXT NOT NULL CHECK (status IN ('active', 'done')),
  name TEXT NOT NULL DEFAULT '',
  goal TEXT NOT NULL DEFAULT '',
  cwd TEXT NOT NULL DEFAULT '',
  adapter TEXT NOT NULL,
  adapter_config TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (source, hostname, session_id)
);
```

On each connection set:

```ruby
database.busy_timeout = 5_000
database.execute("PRAGMA journal_mode = WAL")
database.execute("PRAGMA foreign_keys = ON")
```

Use `BEGIN IMMEDIATE` for read-compare-write mutations. Serialize `adapter_config` with `JSON.generate` and parse it into a hash on read. Format timestamps with `time.utc.iso8601(6)`.

- [ ] **Step 6: Add dependency, test runner, version, and license**

`Gemfile` must include:

```ruby
source "https://rubygems.org"
gem "sqlite3"
```

`Rakefile` must load `Rake::TestTask` over `test/**/*_test.rb`. `VERSION` contains `0.1.0` plus one newline. `LICENSE` is the standard MIT License with copyright `2026 Brian John`.

- [ ] **Step 7: Run the focused and full public tests**

Run:

```bash
ruby -Ilib:test test/database_test.rb
rake test
```

Expected: all tests pass.

- [ ] **Step 8: Commit the persistence layer in the public repository**

Use the managed commit helper from the staged repository:

```bash
~/.pi/agent/skills/z-commit/commit.sh \
  -m "Add deterministic session persistence" \
  LICENSE Gemfile Rakefile VERSION lib test
```

Expected: one root commit with no AI attribution.

---

### Task 2: Build Public CLI and Action-Based Adapter Dispatch

**Files:**
- Create in staged public repository: `bin/asr`
- Create in staged public repository: `lib/agent_session_registry/adapter.rb`
- Create in staged public repository: `lib/agent_session_registry/cli.rb`
- Create in staged public repository: `test/adapter_test.rb`
- Create in staged public repository: `test/cli_test.rb`
- Create in staged public repository: `README.md`

**Interfaces:**
- Consumes: Task 1 `Identity`, `Database`, and record hashes.
- Produces: `AgentSessionRegistry::Adapter.new(directory:)` with `spawn(name:, action:, key:, config:)` and `wait(pid)`.
- Produces: `AgentSessionRegistry::CLI.run(argv, out:, err:, env:) -> Integer`.
- Produces executable commands `asr list|show|register|update|done|resume`.
- Documents environment variables `ASR_DATABASE_PATH` and `ASR_ADAPTER_DIR`.

- [ ] **Step 1: Write adapter and CLI tests before implementation**

Adapter tests create executable fixtures under a temporary adapter directory. Assert the adapter receives these four arguments in order:

```ruby
[adapter_path, "resume", key, JSON.generate(config)]
```

Cover rejection of:

- adapter names with `/`, `..`, uppercase, or shell metacharacters;
- missing files;
- non-executable files;
- symlinks that resolve outside the adapter directory;
- unsupported action names at the CLI boundary.

CLI subprocess tests must invoke the production `bin/asr` with temporary paths:

```ruby
env = {
  "ASR_DATABASE_PATH" => database_path,
  "ASR_ADAPTER_DIR" => adapter_directory
}
stdout, stderr, status = Open3.capture3(
  env,
  File.join(repo_root, "bin/asr"),
  "register",
  "--source", "pi",
  "--session-id", "session-1",
  "--local",
  "--status", "active",
  "--name", "Registry work",
  "--goal", "Build registry",
  "--cwd", "/work/repo",
  "--adapter", "pi-local",
  "--adapter-config", '{"session_file":"/sessions/one.jsonl"}'
)
assert status.success?, stderr
```

Cover every command, `--json`, default active filtering, `--all`, `--remote`, exact key parsing, local field-form update/done, help, bad options, missing records, and adapter exit-status propagation.

- [ ] **Step 2: Run tests and confirm the intended red state**

Run:

```bash
ruby -Ilib:test test/adapter_test.rb
ruby -Ilib:test test/cli_test.rb
```

Expected: failures because adapter and CLI classes are missing.

- [ ] **Step 3: Implement safe adapter discovery and launch**

Resolve the configured adapter directory with `File.realpath`. Resolve the candidate as one direct child. Require the candidate's real path to have the adapter directory plus a separator as its prefix. Require `File.file?` and `File.executable?`.

Launch without a shell:

```ruby
pid = Process.spawn(
  candidate,
  action,
  key,
  JSON.generate(config),
  in: $stdin,
  out: $stdout,
  err: $stderr
)
```

The CLI must update status to active only after `Process.spawn` returns a PID, then wait and return the adapter's exit status.

- [ ] **Step 4: Implement CLI parsing and exact command contracts**

Use `OptionParser`. Defaults are:

```ruby
database_path = env.fetch(
  "ASR_DATABASE_PATH",
  File.join(Dir.home, ".local/state/agent-session-registry/registry.sqlite3")
)
adapter_directory = env.fetch(
  "ASR_ADAPTER_DIR",
  File.join(Dir.home, ".local/lib/agent-session-registry/adapters")
)
```

`register` requires source, session ID, explicit `--local` or `--remote`, status, adapter, and object-valued adapter config. Hostname defaults locally only for `--local`; remote registration requires `--hostname`.

`update` and `done` accept either one rendered key or `--source` plus `--session-id`; field form defaults hostname to the canonical local hostname.

`list` defaults to active. `--all` removes the status filter. `--status` and `--all` are mutually exclusive. `--remote` filters remote records.

Human list output uses stable YAML-like records with `---` separators and includes:

```text
key: pi:workstation:session-1
status: active
location: local
hostname: workstation
name: Registry work
goal: Build registry
cwd: /work/repo
updated_at: 2026-08-09T12:00:00.000000Z
resume: asr resume pi:workstation:session-1
```

Omit `goal` only when it is empty or identical to `name`. JSON output contains arrays for list and one object for show/mutations.

Map input and missing-record errors to exit `2`, storage/runtime errors to exit `1`, and success to exit `0`. Do not print a Ruby backtrace for expected user errors.

- [ ] **Step 5: Create the thin executable**

`bin/asr` must contain only startup wiring:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "agent_session_registry/cli"

exit AgentSessionRegistry::CLI.run(
  ARGV,
  out: $stdout,
  err: $stderr,
  env: ENV
)
```

Set mode `0755`.

- [ ] **Step 6: Write complete public documentation**

README sections must cover:

- purpose and per-machine ownership;
- Ruby and `sqlite3` requirements;
- Git installation and `bin/asr`;
- all command examples;
- fixed record columns;
- local and remote registration examples;
- active/done semantics;
- database and adapter environment overrides;
- adapter location and action contract;
- safe adapter example that handles `resume`;
- no daemon and no arbitrary commands;
- test command `rake test`.

- [ ] **Step 7: Run public verification**

Run:

```bash
rake test
ruby -c bin/asr
ruby -c lib/agent_session_registry/adapter.rb
ruby -c lib/agent_session_registry/cli.rb
ASR_DATABASE_PATH="$(mktemp)" bin/asr --help
```

For the smoke test, remove the empty `mktemp` file before SQLite opens it, or use a path under a temporary directory. Expected: tests pass, syntax checks report `Syntax OK`, and help exits `0`.

- [ ] **Step 8: Commit the CLI in the public repository**

Run:

```bash
~/.pi/agent/skills/z-commit/commit.sh \
  -m "Add the agent session registry CLI" \
  README.md bin lib test
```

Expected: one coherent second commit.

---

### Task 3: Review and Publish the Public Repository

**Files:**
- Review all files under staged public repository `tmp/agent-session-registry/`.
- Publish to `https://github.com/f1sherman/agent-session-registry`.

**Interfaces:**
- Consumes: complete tested public repository from Tasks 1 and 2.
- Produces: public Git repository with default branch `main` and tag `v0.1.0`.
- Produces the immutable source NMB pins in Task 4.

- [ ] **Step 1: Verify the complete proposed public content**

Run:

```bash
git -C tmp/agent-session-registry status --short
git -C tmp/agent-session-registry log --oneline --decorate
git -C tmp/agent-session-registry ls-tree -r --name-only HEAD
git -C tmp/agent-session-registry show --stat --oneline HEAD~1..HEAD
```

Also review `git show HEAD` and the root commit. Confirm there are no credentials, machine paths, generated files, AI attribution, or files outside the approved tree.

- [ ] **Step 2: Get explicit public publication authorization**

Show the user:

- destination `f1sherman/agent-session-registry`;
- contribution type: new public GitHub repository;
- exact file tree;
- complete diff/content or a review artifact that contains it;
- planned tag `v0.1.0`;
- MIT License.

Do not publish until the user explicitly authorizes this exact content.

- [ ] **Step 3: Confirm the destination does not already contain unrelated work**

Run:

```bash
gh repo view f1sherman/agent-session-registry \
  --json nameWithOwner,visibility,defaultBranchRef
```

If the repository exists with content that was not created by this workflow, stop and ask rather than overwriting it.

- [ ] **Step 4: Create and push the public repository**

If absent, run from the staged public repository:

```bash
gh repo create f1sherman/agent-session-registry \
  --public \
  --source=. \
  --remote=origin \
  --push
```

If the approved repository exists but is empty, add its HTTPS origin and push `main` without force.

- [ ] **Step 5: Tag the verified release**

Run:

```bash
git tag -a v0.1.0 -m "Release v0.1.0"
git push origin v0.1.0
gh repo view f1sherman/agent-session-registry --web=false
```

Verify the remote `main` commit and `refs/tags/v0.1.0` resolve to the reviewed commits. Do not create a GitHub Release unless the user asks; the pinned Git tag is sufficient.

---

### Task 4: Provision the Pinned Registry and Pi Adapter in NMB

**Files:**
- Modify: `vars/tool_versions.yml`
- Modify: `roles/common/tasks/main.yml`
- Create: `roles/common/files/agent-session-registry/adapters/pi-local`
- Create: `tests/pi-session-registry-adapter.rb`
- Modify: `.github/workflows/integration-test.yml`

**Interfaces:**
- Consumes: public tag `v0.1.0` with executable `bin/asr`.
- Produces: deployed `~/.local/bin/asr`.
- Produces: deployed `~/.local/lib/agent-session-registry/adapters/pi-local`.
- The adapter consumes arguments `(action, registry_key, adapter_config_json)`.

- [ ] **Step 1: Write the failing Pi adapter behavioral test**

The test must execute the production adapter with a fake `pi` earlier in `PATH`. Cover:

- `resume` with readable absolute session file executes `pi --session <file>`;
- unsupported action fails;
- malformed JSON fails;
- non-object JSON fails;
- missing `session_file` fails;
- relative, missing, or unreadable session files fail;
- shell metacharacters remain one literal argument and never execute.

Capture the fake Pi argument vector as JSON rather than comparing a shell string.

- [ ] **Step 2: Run the adapter test and confirm red**

Run:

```bash
ruby tests/pi-session-registry-adapter.rb
```

Expected: failure because the production adapter does not exist.

- [ ] **Step 3: Implement the Pi adapter**

Use Ruby `JSON.parse`, `Pathname`, and `exec`. Its core contract is:

```ruby
action, _registry_key, raw_config = ARGV
abort "Unsupported adapter action: #{action}" unless action == "resume"
config = JSON.parse(raw_config)
abort "Adapter config must be a JSON object" unless config.is_a?(Hash)
session_file = Pathname.new(config.fetch("session_file"))
abort "Session file must be absolute and readable" unless session_file.absolute? && session_file.file? && session_file.readable?
exec "pi", "--session", session_file.to_s
```

Catch `JSON::ParserError` and `KeyError` to print concise diagnostics without backtraces. Set mode `0755`.

- [ ] **Step 4: Add the pinned version**

Add under `tool_versions.git_tags`:

```yaml
# renovate: datasource=github-tags depName=f1sherman/agent-session-registry
agent_session_registry: v0.1.0
```

- [ ] **Step 5: Add idempotent provisioning tasks after managed Ruby setup**

The tasks must:

1. verify/install the `sqlite3` gem with the pinned Ruby;
2. clone the public tag into `~/.local/share/agent-session-registry`;
3. link its `bin/asr` to `~/.local/bin/asr`;
4. create `~/.local/lib/agent-session-registry/adapters` mode `0755`;
5. copy `pi-local` mode `0755`.

Use an idempotent gem probe:

```yaml
- name: Install Ruby sqlite3 gem for agent session registry
  shell: |
    set -euo pipefail
    if {{ mise_bin }} exec ruby@{{ tool_versions.runtimes.ruby }} -- \
      ruby -e 'require "sqlite3"' 2>/dev/null; then
      echo unchanged
    else
      {{ mise_bin }} exec ruby@{{ tool_versions.runtimes.ruby }} -- \
        gem install sqlite3 --no-document
      echo changed
    fi
  args:
    executable: /bin/bash
  register: agent_session_registry_sqlite3
  changed_when: agent_session_registry_sqlite3.stdout_lines[-1] == 'changed'
```

Use Ansible `git` with `version` set to the pinned tag and no local force overwrite. Use Ansible `file` for the executable symlink.

- [ ] **Step 6: Add the material adapter test to CI**

Add one integration-test workflow step:

```yaml
- name: Verify Pi session registry adapter
  run: ruby tests/pi-session-registry-adapter.rb
```

Do not add a static test that restates Ansible task text.

- [ ] **Step 7: Run focused NMB checks**

Run:

```bash
ruby tests/pi-session-registry-adapter.rb
ruby -c roles/common/files/agent-session-registry/adapters/pi-local
ansible-playbook playbook.yml --syntax-check
```

Expected: adapter behavior passes, syntax is valid, and Ansible syntax check passes.

- [ ] **Step 8: Commit NMB provisioning and adapter work**

Use `z-commit` with these paths and an imperative message such as:

```text
Provision the agent session registry
```

---

### Task 5: Publish Pi Session Identity and Add Explicit Completion Skill

**Files:**
- Modify: `roles/common/files/pi/extensions/managed-hooks.ts`
- Modify: `tests/pi-managed-hooks.sh`
- Create: `roles/common/files/config/skills/pi/z-session-done/SKILL.md`

**Interfaces:**
- Consumes deployed `asr` from Task 4.
- Produces serialized `asr register` on persistent `session_start`.
- Produces serialized `asr update --source pi --session-id <id>` for changed names and goals.
- Produces user-only skill command `asr done --source pi --session-id "$PI_SESSION_ID"`.

- [ ] **Step 1: Extend the managed-hook harness with registry state**

Add `getSessionId()` to the mocked SessionManager and capture `asr` calls in the existing `calls` array. Add deferred `asr` results so the test can prove publication ordering.

Use a fixed session ID:

```javascript
let activeSessionId = "019fe7a6-a219-7548-a6ef-1f23885864f4";
// ...
getSessionId() { return activeSessionId; },
```

- [ ] **Step 2: Write failing Pi publication cases**

Add behavioral assertions for:

- persistent `session_start` calls `asr register` with source `pi`, explicit local mode, active status, session ID, current cwd, adapter `pi-local`, and JSON session file config;
- restored goal and current name are included;
- empty session file causes no `asr` call;
- explicit goal update calls field-form `asr update` with the session ID and goal;
- `session_info_changed` calls field-form update with the current name;
- two delayed updates execute in order and leave the newest value last;
- nonzero or thrown CLI failure does not reject the Pi lifecycle handler or goal tool;
- `session_shutdown` never calls `asr done`.

- [ ] **Step 3: Run the managed-hook test and confirm red**

Run:

```bash
bash tests/pi-managed-hooks.sh
```

Expected: new assertions fail because registry publication is missing.

- [ ] **Step 4: Implement serialized registry publication**

Inside the extension factory, add a promise chain independent from tmux identity publication:

```typescript
let registryPublicationChain = Promise.resolve();

function serializeRegistryPublication(operation) {
  const result = registryPublicationChain.then(operation);
  registryPublicationChain = result.catch(() => {});
  return result;
}
```

Add helpers that return early when either session ID or session file is missing. Use `ctx.sessionManager.getSessionId()`, `getSessionFile()`, `getSessionName()`, `ctx.cwd`, and `currentSessionGoal`. Pass every value as a separate `pi.exec` argument. Never build a shell command.

Registration arguments must include:

```text
register --source pi --session-id <id> --local --status active
--name <name> --goal <goal> --cwd <cwd> --adapter pi-local
--adapter-config {"session_file":"<absolute path>"}
```

Update arguments must use:

```text
update --source pi --session-id <id> --name <name>
update --source pi --session-id <id> --goal <goal>
```

Treat a nonzero exit as a warning through `warn`. Registry failure must not alter the already accepted goal or name.

- [ ] **Step 5: Wire lifecycle publication at canonical points**

- Register after `resetSessionGoalLifecycle(ctx)` in `session_start`.
- In the canonical `applySessionGoal` path, update the registry goal only after
  `pi.appendEntry` succeeds and `currentSessionGoal` changes.
- Update the name from `session_info_changed` even outside tmux.
- Do not add shutdown publication.
- Keep all existing tmux behavior and race guards unchanged.

- [ ] **Step 6: Create the user-invoked completion skill**

Use this exact frontmatter and behavior:

```markdown
---
name: z-session-done
description: Mark the current persistent Pi session done. Use only when the user explicitly asks to mark this session done.
disable-model-invocation: true
---

# Mark Current Session Done

Run this only because the user explicitly requested that the current session be marked done.

1. Confirm `PI_SESSION_FILE` and `PI_SESSION_ID` are non-empty.
2. Run `asr done --source pi --session-id "$PI_SESSION_ID"` exactly once.
3. Report the session ID that was marked done.

Do not accept or substitute another session ID. Do not infer completion from task success, verification, pull-request state, shutdown, inactivity, or goodbye wording.
```

The skill must use the bash tool's injected Pi environment. Do not add a custom Pi completion tool.

- [ ] **Step 7: Run focused tests**

Run:

```bash
bash tests/pi-managed-hooks.sh
ruby tests/pi-session-registry-adapter.rb
git diff --check
```

Expected: all tests pass and no whitespace errors exist.

- [ ] **Step 8: Commit Pi publication and skill work**

Use `z-commit` with the extension, managed-hook test, and skill paths. Use an imperative message such as:

```text
Register persistent Pi sessions
```

---

### Task 6: Provision, Verify End to End, Review, and Open the NMB PR

**Files:**
- Verify all NMB feature-branch changes.
- Do not edit deployed files directly.

**Interfaces:**
- Consumes: public `v0.1.0`, NMB provisioning, Pi adapter, hook publication, and completion skill.
- Produces: deployed working registry and an NMB GitHub pull request.

- [ ] **Step 1: Run all focused repository tests from a clean diff**

Run:

```bash
ruby tests/pi-session-registry-adapter.rb
bash tests/pi-managed-hooks.sh
bash tests/tmux-agent-state.sh
ansible-playbook playbook.yml --syntax-check
git diff --check origin/main...HEAD
```

Expected: all commands succeed.

- [ ] **Step 2: Run NMB provisioning from the feature worktree**

Run:

```bash
bin/provision
```

Use the built-in provision lock. Inspect the newest `/tmp/provision-*.log` if the run fails. Confirm its provenance identifies this feature worktree and branch.

- [ ] **Step 3: Verify deployed installation without editing it**

Inspect only:

```bash
readlink ~/.local/bin/asr
~/.local/bin/asr --help
git -C ~/.local/share/agent-session-registry describe --tags --exact-match
ruby -e 'require "sqlite3"; puts SQLite3::VERSION'
test -x ~/.local/lib/agent-session-registry/adapters/pi-local
```

Expected: the link targets the managed clone, the tag is `v0.1.0`, SQLite loads, and the adapter is executable.

- [ ] **Step 4: Exercise the registry with an isolated persistent Pi session**

Start a short persistent Pi session in a temporary project directory with the managed extension loaded. Give it a known name and goal. Use `asr list --json` and `asr show <key> --json` to confirm:

- native Pi UUID;
- canonical local hostname;
- source `pi`;
- `remote: false`;
- status `active`;
- expected name and goal;
- working directory;
- adapter `pi-local`;
- absolute session file config.

Do not use the current development session as destructive test data.

- [ ] **Step 5: Verify explicit done and resume behavior**

For the isolated test session:

1. run the exact skill command contract with that session's injected ID;
2. confirm status becomes done;
3. run `asr resume <key>` in a controlled terminal;
4. exit the resumed session cleanly;
5. confirm session-start registration changed status back to active.

Confirm ordinary shutdown did not mark it done.

- [ ] **Step 6: Run an independent review**

Use the repository review workflow. Review both:

- the published public repository at tag `v0.1.0` for correctness, safety, documentation, and test gaps;
- the NMB branch diff for provisioning, Pi lifecycle races, adapter safety, and scope compliance.

Fix only concrete issues worth addressing now. Any public repository fix requires a new reviewed tag such as `v0.1.1` and a matching NMB version update; never move `v0.1.0`.

- [ ] **Step 7: Run final verification after review fixes**

Repeat the affected public tests, NMB focused tests, `bin/provision`, and the end-to-end path. Record exact commands and results for the PR.

- [ ] **Step 8: Commit any final NMB fixes**

Use `z-commit`. Confirm the NMB worktree is clean afterward.

- [ ] **Step 9: Open the NMB pull request**

Invoke the `pull-request` skill. The PR must describe:

- the user problem;
- the public `f1sherman/agent-session-registry` repository and pinned tag;
- fixed record and status semantics;
- external action adapter contract;
- automatic Pi publication points;
- explicit-only completion safety;
- public and NMB test evidence;
- provisioning and end-to-end evidence;
- any residual risks.

Do not merge locally.
