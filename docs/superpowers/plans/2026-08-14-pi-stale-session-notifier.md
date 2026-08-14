# Pi Stale-Session Notifier Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use engineering:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Notify each running Pi process when deployed Pi resources no longer match the resources that process loaded.

**Architecture:** A generic Ruby publisher fingerprints producer-owned inputs and writes one atomic record per producer. An NMB reconciliation helper describes NMB-owned deployed inputs and runs after provisioning, including failed provisioning. A Pi extension polls the records, keeps process and reload baselines separate, and publishes persistent Pi and tmux status.

**Tech Stack:** Ruby standard library, JavaScript-compatible TypeScript, Bash 3.2-compatible shell, Ansible, Node.js integration tests, tmux.

## Global Constraints

- Producer records live under `${XDG_STATE_HOME:-~/.local/state}/pi-session-staleness/v1/producers/`.
- State directories use mode `0700`; producer records use mode `0600`.
- Producer identifiers match `[a-z0-9][a-z0-9-]{0,63}`.
- Producer records use schema version `1`.
- Polling runs every 10 seconds; a directory watch can only request an earlier poll.
- Reload state is replaced only after a complete valid snapshot reaches `session_start`.
- Restart state survives `/reload` through a stable `Symbol.for(...)` process-global key.
- Restart warnings take precedence over reload warnings.
- The extension never calls `ctx.reload()` and never exits Pi.
- Check mode does not publish. Ansible `--diff` still applies changes and therefore does publish.
- State records contain fingerprints and fixed reasons only. They contain no configuration contents or credentials.
- Public files, commits, and PR text use generic terms only.

---

## File Structure

- `roles/common/files/bin/pi-session-staleness-publish`: Validate manifests, hash inputs, and atomically reconcile one producer classification.
- `roles/common/files/bin/pi-session-staleness-reconcile-new-machine-bootstrap`: Build NMB reload and restart manifests from deployed state and invoke the publisher.
- `roles/common/files/pi/extensions/pi-session-staleness.ts`: Poll producer state and publish Pi and tmux status.
- `tests/pi-session-staleness-publish.rb`: Execute the production publisher and verify fingerprints, validation, locking, and atomic replacement.
- `tests/pi-session-staleness-extension.sh`: Load the production extension under Node with injected file-system, timer, UI, and tmux adapters.
- `tests/pi-session-staleness-provisioning.sh`: Verify cleanup reconciliation, failure precedence, and check-mode suppression through the production `bin/provision` entry point.
- `roles/common/files/bin/tmux-indicator-glyphs`: Map stale state to the local window badge.
- `roles/common/files/bin/tmux-window-label`: read local and remote stale state and pass it to the glyph mapper.
- `roles/common/files/bin/tmux-remote-title`: add stale state to the third remote marker field.
- `tests/tmux-label-contract.sh`: Verify local and remote stale marker compatibility.
- `roles/common/tasks/main.yml`: Install the publisher, helper, extension, and baseline in safe order.
- `.github/workflows/integration-test.yml`: Run the new production-artifact tests.
- `bin/provision`: Reconcile from the cleanup trap after possible mutations.
- `docs/superpowers/specs/2026-08-14-pi-stale-session-notifier-design.md`: Remove private terminology and resolve the Ansible `--diff` contradiction.

---

### Task 1: Make the approved design safe for the public repository

**Files:**
- Modify: `docs/superpowers/specs/2026-08-14-pi-stale-session-notifier-design.md`

**Interfaces:**
- Consumes: The approved stale-session behavior.
- Produces: Public design language and the binding rule that check mode skips publication while apply mode with `--diff` publishes.

- [ ] **Step 1: Replace private ownership details with the generic producer contract**

Keep NMB as the generic feature owner. Replace every named private repository, private package family, private environment, and employer-specific example with one of these terms:

```text
participating repository
private producer
managed package
remote development host
project package store
```

Keep `new-machine-bootstrap` as the only initial producer identifier. Describe later producer enrollment without assigning a private identifier.

- [ ] **Step 2: Correct the provisioning-mode rule**

Replace the contradictory rule with this exact behavior:

```text
Ansible check mode never publishes because it does not change effective state.
An apply run publishes even when --diff is enabled, because --diff changes only
reporting and does not make the run read-only.
```

- [ ] **Step 3: Scan the design for prohibited or stale language**

Inspect the complete design and its diff. Confirm that it contains only NMB,
generic producer, managed package, and remote development terminology. Confirm
that the generic replacements preserve the technical meaning.

- [ ] **Step 4: Commit the public design correction**

```bash
git add \
  docs/superpowers/specs/2026-08-14-pi-stale-session-notifier-design.md \
  docs/superpowers/plans/2026-08-14-pi-stale-session-notifier.md
git commit -m "docs: plan Pi stale-session notifier"
```

Expected: one documentation commit containing the public design and plan.

---

### Task 2: Implement the generic state publisher

**Files:**
- Create: `roles/common/files/bin/pi-session-staleness-publish`
- Create: `tests/pi-session-staleness-publish.rb`

**Interfaces:**
- Consumes: `reconcile --producer ID --classification reload|restart --reason TEXT --manifest FILE`.
- Produces: `${XDG_STATE_HOME:-$HOME/.local/state}/pi-session-staleness/v1/producers/ID.json` with `schema`, `producer`, and optional `reload` and `restart` objects.
- Produces: Manifest schema `{ "schema": 1, "inputs": PathInput[] | ValueInput[] }`, where a path input is `{ "type": "path", "name": String, "root": AbsolutePath, "path": RelativePath }` and a value input is `{ "type": "value", "name": String, "value": String }`.

**Reviewer Verification:**
- Run `ruby tests/pi-session-staleness-publish.rb`. Expected final line: `Pi session staleness publisher behavior passed`.

- [ ] **Step 1: Write publisher behavior tests against the production command**

Create a direct Ruby test harness. It must use `Open3.capture3`, temporary `HOME` and `XDG_STATE_HOME` directories, and the production command path. Add named cases for:

```ruby
CASES = [
  :stable_directory_order,
  :file_content_change,
  :symlink_target_change,
  :executable_bit_change,
  :missing_path_change,
  :value_change,
  :no_op_preserves_bytes_and_mtime,
  :classification_updates_are_independent,
  :producer_records_are_independent,
  :invalid_operation,
  :invalid_identifier,
  :invalid_classification,
  :invalid_reason,
  :invalid_manifest_schema,
  :duplicate_input_name,
  :relative_root,
  :escaping_relative_path,
  :prior_record_survives_hash_failure,
  :readers_never_observe_partial_json,
].freeze
```

The no-op case must save both `File.binread(record)` and `File.stat(record).mtime` before the second reconcile. The atomic case must run repeated reconcile operations in one process while another process repeatedly parses the record with `JSON.parse`.

- [ ] **Step 2: Run the publisher test and verify the expected failure**

Run:

```bash
ruby tests/pi-session-staleness-publish.rb
```

Expected: FAIL because `roles/common/files/bin/pi-session-staleness-publish` does not exist.

- [ ] **Step 3: Implement strict CLI and manifest validation**

Use only Ruby standard-library modules:

```ruby
require "digest"
require "fileutils"
require "json"
require "optparse"
require "pathname"
require "time"

PRODUCER_PATTERN = /\A[a-z0-9][a-z0-9-]{0,63}\z/
CLASSIFICATIONS = %w[reload restart].freeze
MAX_REASON_BYTES = 200
MANIFEST_KEYS = %w[schema inputs].freeze
PATH_KEYS = %w[type name root path].freeze
VALUE_KEYS = %w[type name value].freeze
```

Reject unknown keys, duplicate names, non-string values, non-absolute roots, empty names, `.`/`..` path segments, NUL bytes, unsupported schema versions, and reasons longer than 200 bytes. Resolve the state location from `XDG_STATE_HOME`, then `HOME/.local/state`.

- [ ] **Step 4: Implement deterministic fingerprinting**

Hash a sorted canonical stream. For each path input, use `File.lstat`. Do not follow symbolic links. Directory entries sort by byte value. Each entry contributes input name, relative path, type, executable-bit state, symlink target, and file bytes. Missing inputs contribute the literal type `missing`. Ignore timestamps, ownership, and non-executable mode bits.

Use length-prefixed fields so content cannot create ambiguous boundaries:

```ruby
def add_field(digest, value)
  bytes = value.to_s.b
  digest << [bytes.bytesize].pack("Q>") << bytes
end
```

Return `sha256:#{digest.hexdigest}`.

- [ ] **Step 5: Implement locked atomic reconciliation**

Create the state and producer directories with mode `0700`. Lock `ID.lock` with `File::LOCK_EX`. Parse and validate an existing record before changing it. If the requested generation is unchanged, exit without writing. Otherwise preserve the other classification and write:

```ruby
record[classification] = {
  "generation" => generation,
  "changedAt" => Time.now.utc.iso8601(3),
  "reason" => reason,
}
```

Write compact JSON plus one newline to a same-directory temporary file. Set mode `0600`, flush, call `fsync`, rename over the destination, and `fsync` the directory. On any validation, read, hash, lock, or write failure, print one prefixed error to stderr, exit nonzero, and leave a valid prior record unchanged.

- [ ] **Step 6: Run the publisher tests**

Run:

```bash
ruby tests/pi-session-staleness-publish.rb
```

Expected: all cases pass and the final success line is printed.

- [ ] **Step 7: Commit the publisher**

```bash
git add \
  roles/common/files/bin/pi-session-staleness-publish \
  tests/pi-session-staleness-publish.rb
git commit -m "feat: publish Pi resource fingerprints"
```

Expected: one focused publisher commit.

---

### Task 3: Reconcile NMB-owned deployed inputs through provisioning cleanup

**Files:**
- Create: `roles/common/files/bin/pi-session-staleness-reconcile-new-machine-bootstrap`
- Create: `tests/pi-session-staleness-provisioning.sh`
- Modify: `bin/provision`

**Interfaces:**
- Consumes: `pi-session-staleness-publish` and deployed files under `~/.pi/agent`, `~/.local/bin`, the managed Pi package root, and the managed Node.js root.
- Produces: `new-machine-bootstrap` reload and restart classifications.
- Produces: `PI_SESSION_STALENESS_RECONCILE_BIN` as a test-only command override for `bin/provision`.

**Reviewer Verification:**
- Run `bash tests/pi-session-staleness-provisioning.sh`. Expected final line: `Pi session staleness provisioning behavior passed`.

- [ ] **Step 1: Write provisioning lifecycle tests**

Create a Bash test that copies `bin/provision` and `bin/provision-lock` to a temporary repository, stubs `ansible-playbook`, and sets `PI_SESSION_STALENESS_RECONCILE_BIN` to a recording stub. Cover these observable cases:

```text
successful apply: reconciler runs once and exit status is zero
failed apply: reconciler runs once and original Ansible status wins
successful apply plus reconcile failure: reconcile status makes provision fail
failed apply plus reconcile failure: original Ansible status wins and both errors print
--check: reconciler does not run
--check --diff: reconciler does not run
--diff apply: reconciler runs
failure before Ansible starts: reconciler does not run
```

Keep all stubs on a temporary `PATH`. Set `OSTYPE=linux-gnu`, `HOME`, `PROVISION_LOG_DIR`, and a temporary Git repository so the production script follows its Linux path without changing the machine.

- [ ] **Step 2: Run the provisioning test and verify the expected failure**

Run:

```bash
bash tests/pi-session-staleness-provisioning.sh
```

Expected: FAIL because `bin/provision` does not call the reconciler.

- [ ] **Step 3: Implement the deployed NMB reconciliation helper**

Write the helper in Ruby so JSON values are generated without shell quoting. Resolve the publisher from the helper’s directory. Create two temporary manifests and invoke the publisher twice.

The reload manifest must include these producer-owned effective inputs:

```text
~/.pi/agent/keybindings.json
~/.pi/agent/AGENTS.md.d/00-base.md
~/.pi/agent/extensions/managed-hooks.ts
~/.pi/agent/extensions/main-worktree-guard.ts
~/.pi/agent/extensions/pi-attention-bell.ts
~/.pi/agent/extensions/spec-shortcut.ts
~/.pi/agent/extensions/pi-session-staleness.ts
~/.pi/agent/extensions/subagent/config.json
~/.pi/agent/npm/node_modules/pi-session-manager
these exact deployed Pi skill directories:
  z-approve-spec, z-catchup, z-commit, z-convert-skill-from-claude,
  z-convert-skill-from-codex, z-create-handoff, z-create-ics,
  z-deep-research, z-done, z-fix, z-generate-codex-auth, z-humanizer,
  z-macos-keychain-secrets, z-quick-pr, z-recover-agent-sessions,
  z-resume-claude-session, z-resume-codex-session, z-resume-handoff,
  z-spec-first, z-stop-skill, and z-update-session-name
```

Add value inputs for the managed settings subset and model override subset. Parse the deployed JSON and serialize these selected values with sorted JSON keys:

```ruby
managed_settings = {
  "hideThinkingBlock" => settings["hideThinkingBlock"],
  "quietStartup" => settings["quietStartup"],
  "collapseChangelog" => settings["collapseChangelog"],
  "mainWorktreeGuardRoles" => %w[
    worker reviewer delegate planner oracle scout context-builder researcher
  ].to_h { |role| [role, guard_present_for_role?(settings, role)] },
}
```

Select only `gpt-5.6-luna`, `gpt-5.6-sol`, and `gpt-5.6-terra` under the
`openai-codex` provider. Do not hash the complete shared `settings.json`,
`models.json`, skills directory, or package store.

The restart manifest must include:

```text
~/.local/bin/pi symbolic link
managed Pi package root returned by mise
managed Node.js executable returned by mise
Pi package version value
Node.js version value
```

Use fixed reasons `Managed Pi resources changed` and `Managed Pi runtime changed`. If discovery or either publisher call fails, print a prefixed error and exit nonzero.

- [ ] **Step 4: Add cleanup reconciliation without hiding the primary failure**

In `bin/provision`, add `PLAYBOOK_STARTED=false`, `SKIP_STALENESS_PUBLISH=false`, and argument detection for `--check` and `-C`. Set `PLAYBOOK_STARTED=true` immediately before the Ansible pipeline.

Change the EXIT trap to capture `$?`, disable recursive EXIT handling, and run the reconciler only when the playbook started and check mode is off. Resolve the command in this order:

```bash
${PI_SESSION_STALENESS_RECONCILE_BIN:-}
$HOME/.local/bin/pi-session-staleness-reconcile-new-machine-bootstrap
```

If provisioning succeeded and reconciliation fails, return the reconciliation status. If provisioning already failed, preserve the original status and log the reconciliation failure as secondary. Always release the provision lock and print the log path.

- [ ] **Step 5: Run publisher and provisioning tests**

Run:

```bash
ruby tests/pi-session-staleness-publish.rb
bash tests/pi-session-staleness-provisioning.sh
```

Expected: both success lines print.

- [ ] **Step 6: Commit provisioning reconciliation**

```bash
git add \
  bin/provision \
  roles/common/files/bin/pi-session-staleness-reconcile-new-machine-bootstrap \
  tests/pi-session-staleness-provisioning.sh
git commit -m "feat: reconcile Pi state after provisioning"
```

Expected: one lifecycle commit.

---

### Task 4: Implement the Pi watcher extension

**Files:**
- Create: `roles/common/files/pi/extensions/pi-session-staleness.ts`
- Create: `tests/pi-session-staleness-extension.sh`

**Interfaces:**
- Consumes: valid producer records from the versioned state directory.
- Consumes: injected test adapters from `globalThis[Symbol.for("nmb.pi-session-staleness.adapters")]` when present.
- Produces: status key `pi-session-staleness`, notifications, logs, and tmux pane option `@pi_stale`.
- Produces: process state at `globalThis[Symbol.for("nmb.pi-session-staleness.process-state")]`.

**Reviewer Verification:**
- Run `bash tests/pi-session-staleness-extension.sh`. Expected final line: `Pi session staleness extension behavior passed`.

- [ ] **Step 1: Write the Node integration harness**

Copy the production `.ts` file to a temporary `.mjs` file and import it with a cache-busting query. Provide fake adapters for:

```javascript
{
  readDirectory,
  readFile,
  watchDirectory,
  setInterval,
  clearInterval,
  log,
  exec,
  stateDirectory,
}
```

Provide a fake Pi API that records `session_start` and `session_shutdown` handlers. Provide fake `ctx.ui.theme.fg`, `setStatus`, and `notify` methods. Add cases for startup baseline, later producer enrollment, reload transition, restart transition, restart precedence, notification deduplication, severity escalation, malformed state, unsupported schema, missing directory, restored state, tmux publication, shutdown cleanup, reload replacement, and process-global restart persistence.

- [ ] **Step 2: Run the extension test and verify the expected failure**

Run:

```bash
bash tests/pi-session-staleness-extension.sh
```

Expected: FAIL because the production extension does not exist.

- [ ] **Step 3: Implement strict snapshot parsing and baseline state**

Keep the TypeScript valid as plain JavaScript so the existing Node harness can import a copied `.mjs` file. Validate exact schema version `1`, matching producer name, optional classifications, `sha256:` generations, ISO timestamps, and bounded fixed reasons.

Use these process-global data shapes:

```javascript
{
  restartBaseline: Map,
  restartStale: Map,
  notifications: Set,
  failures: Set,
}
```

Each extension instance owns `reloadBaseline`, `knownRecords`, its timer, its watch handle, and its current context. The first successful complete snapshot initializes both baselines. A replacement extension replaces only `reloadBaseline`; it reuses `restartBaseline`.

- [ ] **Step 4: Implement polling and monotonic error handling**

Start resources only from `session_start`. Poll immediately and then every 10,000 ms. A directory watch can schedule an early coalesced poll, but polling remains active if the watch fails or atomic rename invalidates it.

Merge valid records into `knownRecords`. One invalid producer must not hide stale state from valid producers. Missing or unreadable records must not clear known stale state. A later valid generation that matches the reload baseline can clear reload staleness. Once observed, restart staleness remains set for the process lifetime.

Deduplicate each distinct failure log and each `{producer, classification, generation}` notification with process-global sets.

- [ ] **Step 5: Implement Pi status and notifications**

Publish these exact status strings with theme colors:

```javascript
ctx.ui.theme.fg("warning", "↻ Pi changed — /reload")
ctx.ui.theme.fg("error", "⟳ Pi changed — restart Pi")
ctx.ui.theme.fg("warning", "Pi staleness check failed")
```

Use `ctx.ui.setStatus("pi-session-staleness", value)`. A stale warning is stronger than a check-failed warning. The first notification for a generation includes producer and reason. Notify again only for a later generation or escalation from reload to restart.

- [ ] **Step 6: Implement tmux publication and shutdown**

When `TMUX_PANE` exists, call `pi.exec("tmux", ...)` to set `@pi_stale` to `reload` or `restart`, or unset it when current. After a changed option, request:

```javascript
pi.exec("tmux-window-label", [process.env.TMUX_PANE])
pi.exec("tmux-remote-title", ["publish"])
```

Rate-limit tmux errors through the same distinct-failure mechanism. On `session_shutdown`, stop the timer and watch, clear the status, and unset `@pi_stale`. The replacement instance republishes surviving restart state at its `session_start`.

- [ ] **Step 7: Run the extension test**

Run:

```bash
bash tests/pi-session-staleness-extension.sh
```

Expected: all integration cases pass and the final success line prints.

- [ ] **Step 8: Commit the extension**

```bash
git add \
  roles/common/files/pi/extensions/pi-session-staleness.ts \
  tests/pi-session-staleness-extension.sh
git commit -m "feat: warn stale Pi processes"
```

Expected: one focused extension commit.

---

### Task 5: Extend local and remote tmux indicator transport

**Files:**
- Modify: `roles/common/files/bin/tmux-indicator-glyphs`
- Modify: `roles/common/files/bin/tmux-window-label`
- Modify: `roles/common/files/bin/tmux-remote-title`
- Modify: `tests/tmux-label-contract.sh`

**Interfaces:**
- Consumes: third `tmux-indicator-glyphs` argument `reload|restart|empty`.
- Consumes: pane option `@pi_stale`.
- Produces: `[nmb-ind=<activity>,<pr-state>,<pi-stale>]` while accepting the old two-field form.
- Produces: `↻` for reload and `⟳` for restart.

**Reviewer Verification:**
- Run `bash tests/tmux-label-contract.sh`. Expected final line: `tmux label race checks complete`.

- [ ] **Step 1: Add failing local and remote contract cases**

Extend the tmux stub to return `@pi_stale`. Add exact assertions for:

```text
local reload badge
local restart badge
restart badge with activity and PR state
old two-field remote marker
new reload three-field remote marker
new restart three-field remote marker
unknown stale value renders no badge
remote marker is stripped from the visible task label
active-pane recalculation reads the selected pane state
```

- [ ] **Step 2: Run the tmux contract and verify the expected failure**

Run:

```bash
bash tests/tmux-label-contract.sh
```

Expected: FAIL on the first new stale badge assertion.

- [ ] **Step 3: Add stale glyph mapping**

Update `tmux-indicator-glyphs` to accept `pi_stale="${3:-}"`. Append stale state after activity and PR glyphs:

```bash
case "$pi_stale" in
  reload) out+='#[fg=#ffff00]↻' ;;
  restart) out+='#[fg=#cc6666]⟳' ;;
esac
```

Keep one trailing space when any glyph exists.

- [ ] **Step 4: Parse and publish the third marker field**

In `tmux-remote-title`, read `@pi_stale` and publish the marker when any of the three fields is nonempty:

```text
[nmb-ind=activity,pr_state,pi_stale]
```

In `tmux-window-label`, parse up to three comma-separated fields. Missing third fields remain empty. Read local `@pi_stale` only for a live Pi pane. Pass all three fields to `tmux-indicator-glyphs`. Keep local state ahead of remote fallback state.

- [ ] **Step 5: Run the tmux contract**

Run:

```bash
bash tests/tmux-label-contract.sh
```

Expected: all local, remote, compatibility, stripping, and race checks pass.

- [ ] **Step 6: Commit tmux transport**

```bash
git add \
  roles/common/files/bin/tmux-indicator-glyphs \
  roles/common/files/bin/tmux-window-label \
  roles/common/files/bin/tmux-remote-title \
  tests/tmux-label-contract.sh
git commit -m "feat: show stale Pi tmux badges"
```

Expected: one tmux compatibility commit.

---

### Task 6: Install the feature and establish the first baseline safely

**Files:**
- Modify: `roles/common/tasks/main.yml`
- Modify: `.github/workflows/integration-test.yml`

**Interfaces:**
- Consumes: production publisher, NMB reconciler, watcher extension, and tests from Tasks 2–5.
- Produces: deployed commands in `~/.local/bin`, initial producer baseline, and watcher in `~/.pi/agent/extensions`.

**Reviewer Verification:**
- Run `bin/provision`, then run `bin/provision` again. Compare the producer record bytes and mtime before and after the second run. Expected: identical bytes and mtime.

- [ ] **Step 1: Add production-artifact tests to CI**

Add these workflow steps after the existing Pi tests:

```yaml
      - name: Verify Pi session staleness publisher
        run: ruby tests/pi-session-staleness-publish.rb

      - name: Verify Pi session staleness provisioning
        run: bash tests/pi-session-staleness-provisioning.sh

      - name: Verify Pi session staleness extension
        run: bash tests/pi-session-staleness-extension.sh
```

The existing tmux contract step covers transport.

- [ ] **Step 2: Install executable helpers before Pi resource mutations**

Add copy tasks near the existing `~/.local/bin` tasks:

```yaml
- name: Install Pi session staleness publisher
  copy:
    src: bin/pi-session-staleness-publish
    dest: '{{ ansible_facts["user_dir"] }}/.local/bin/pi-session-staleness-publish'
    mode: '0755'

- name: Install NMB Pi session staleness reconciler
  copy:
    src: bin/pi-session-staleness-reconcile-new-machine-bootstrap
    dest: '{{ ansible_facts["user_dir"] }}/.local/bin/pi-session-staleness-reconcile-new-machine-bootstrap'
    mode: '0755'
```

Do not install the watcher in this section.

- [ ] **Step 3: Reconcile the initial baseline after all managed Pi inputs**

After Pi skills and other NMB-owned Pi resources are installed, invoke the deployed helper:

```yaml
- name: Reconcile managed Pi session staleness baseline
  command: '{{ ansible_facts["user_dir"] }}/.local/bin/pi-session-staleness-reconcile-new-machine-bootstrap'
  environment:
    HOME: '{{ ansible_facts["user_dir"] }}'
    PATH: '{{ ansible_facts["user_dir"] }}/.local/bin:{{ ansible_facts["user_dir"] }}/.local/share/mise/shims:{{ ansible_facts["env"]["PATH"] }}'
  changed_when: false
  when: not ansible_check_mode
```

This task must appear before watcher installation. A publisher error fails provisioning.

- [ ] **Step 4: Install the watcher after the baseline exists**

Immediately after baseline reconciliation, install the watcher and reconcile
again:

```yaml
- name: Install Pi session staleness watcher
  copy:
    src: pi/extensions/pi-session-staleness.ts
    dest: '{{ ansible_facts["user_dir"] }}/.pi/agent/extensions/pi-session-staleness.ts'
    mode: '0644'

- name: Reconcile managed Pi baseline after watcher installation
  command: '{{ ansible_facts["user_dir"] }}/.local/bin/pi-session-staleness-reconcile-new-machine-bootstrap'
  environment:
    HOME: '{{ ansible_facts["user_dir"] }}'
    PATH: '{{ ansible_facts["user_dir"] }}/.local/bin:{{ ansible_facts["user_dir"] }}/.local/share/mise/shims:{{ ansible_facts["env"]["PATH"] }}'
  changed_when: false
  when: not ansible_check_mode
```

The first reconcile creates a producer record before the watcher is discoverable.
It includes the watcher path as a missing sentinel. The second reconcile records
the installed watcher bytes for direct playbook runs. The `bin/provision` cleanup
reconcile is then a no-op. Existing processes require the documented one-time
reload or restart.

- [ ] **Step 5: Run focused tests**

Run:

```bash
ruby tests/pi-session-staleness-publish.rb
bash tests/pi-session-staleness-provisioning.sh
bash tests/pi-session-staleness-extension.sh
bash tests/tmux-label-contract.sh
```

Expected: all four commands pass.

- [ ] **Step 6: Run syntax and playbook checks**

Run:

```bash
ruby -c roles/common/files/bin/pi-session-staleness-publish
ruby -c \
  roles/common/files/bin/pi-session-staleness-reconcile-new-machine-bootstrap
bash -n bin/provision
bash -n roles/common/files/bin/tmux-indicator-glyphs
bash -n roles/common/files/bin/tmux-window-label
bash -n roles/common/files/bin/tmux-remote-title
ansible-playbook playbook.yml --syntax-check
```

Expected: Ruby reports `Syntax OK`, shell checks are silent, and Ansible reports no syntax error.

- [ ] **Step 7: Commit provisioning and CI wiring**

```bash
git add roles/common/tasks/main.yml .github/workflows/integration-test.yml
git commit -m "feat: install Pi stale-session notifier"
```

Expected: one installation commit.

---

### Task 7: Rebase, provision, and capture end-to-end evidence

**Files:**
- Modify only if verification finds a defect.

**Interfaces:**
- Consumes: complete feature branch.
- Produces: a clean branch based on current `origin/main`, passing automated tests, deployed behavior, and reviewer-facing command evidence.

**Reviewer Verification:**
- Use the command outputs and state comparisons captured in this task as the PR Test Plan.

- [ ] **Step 1: Rebase onto current main**

Run:

```bash
git fetch origin
git rebase origin/main
```

Expected: the feature commits replay cleanly. Resolve only genuine conflicts and rerun affected tests.

- [ ] **Step 2: Run the complete automated verification set**

Run:

```bash
ruby tests/pi-session-staleness-publish.rb
bash tests/pi-session-staleness-provisioning.sh
bash tests/pi-session-staleness-extension.sh
bash tests/tmux-label-contract.sh
ansible-playbook playbook.yml --syntax-check
```

Expected: all commands pass.

- [ ] **Step 3: Provision from this worktree**

Run:

```bash
bin/provision
```

Expected: provisioning succeeds and logs successful stale-state reconciliation. Record the generated provision log path.

- [ ] **Step 4: Prove no-op stability**

Save the producer record checksum and mtime, run a second provision, and compare:

```bash
record="${XDG_STATE_HOME:-$HOME/.local/state}/pi-session-staleness/v1/"\
"producers/new-machine-bootstrap.json"
sha256_before="$(shasum -a 256 "$record")"
mtime_before="$(stat -f %m "$record" 2>/dev/null || stat -c %Y "$record")"
bin/provision
sha256_after="$(shasum -a 256 "$record")"
mtime_after="$(stat -f %m "$record" 2>/dev/null || stat -c %Y "$record")"
printf '%s\n%s\n%s\n%s\n' \
  "$sha256_before" "$sha256_after" "$mtime_before" "$mtime_after"
```

Expected: checksums match and mtimes match.

- [ ] **Step 5: Verify reload and restart behavior with two Pi processes**

Start two Pi processes after the rollout reload. Change one deployed reload-class fixture through a controlled temporary test manifest, then reconcile. Confirm both processes show the yellow footer and tmux `↻` badge within 15 seconds. Run `/reload` in one process and confirm only that process clears.

Then publish a controlled restart-class value change. Confirm both processes show the red footer and `⟳` badge. Run `/reload` and confirm the red warning remains. Start a new Pi process and confirm it has no warning.

After verification, stop the test Pi processes and remove the temporary producer
record. Start one fresh Pi process and confirm that the temporary producer does
not appear. Do not edit deployed managed files directly.

- [ ] **Step 6: Verify partial-failure publication without changing the machine**

Use the production provisioning test as the safe failure artifact:

```bash
bash tests/pi-session-staleness-provisioning.sh
```

Expected: it proves cleanup runs after a stubbed failed playbook and preserves the original failure status.

- [ ] **Step 7: Confirm repository and public-language state**

Run `git status --short` and inspect all feature diffs. Expected: the worktree
is clean and no feature file contains a private repository, package,
environment, ticket, or employer reference.

- [ ] **Step 8: Request review and prepare the pull request**

Use the repository review workflow. Include these concrete artifacts in the PR Test Plan:

```text
publisher production test output
extension production test output
tmux contract output
Ansible syntax-check output
first and second provision log paths
matching no-op producer checksum and mtime
manual two-process reload and restart observations
```

Expected: review finds no unresolved correctness, security, or public-language issue.
