# OmniWM Login Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reapply deterministic OmniWM workspace rules once after graphical login on `Brians-MacBook-Pro` without focusing or guessing windows.

**Architecture:** A JSON manifest is the single source for managed workspace assignments. The existing settings reconciler converts the manifest to OmniWM rules, while a bounded Ruby login helper classifies live windows from the same manifest and asks OmniWM to reapply its rules to exact live IDs. A RunAtLoad LaunchAgent starts the helper at login, but provisioning never loads or runs it.

**Tech Stack:** Ruby standard library, JSON, OmniWM IPC, launchd, Ansible, Minitest

**Spec:** `docs/superpowers/specs/2026-09-02-omniwm-login-recovery-design.md`

## Global Constraints

- Install and run this feature only through the existing exact `Brians-MacBook-Pro` OmniWM host gate.
- Do not run recovery, move windows, focus windows, restart OmniWM, or load the recovery LaunchAgent during provisioning.
- Apply a rule only when one manifest assignment matches one exact live window.
- Leave unknown, titleless, and ambiguous windows unchanged.
- Do not use workspace 1 or workspace 10 as a fallback.
- Do not edit OmniWM runtime state.
- Recovery runs once per LaunchAgent invocation and has bounded waits.
- Update `docs/omniwm-cheatsheet.md` when the managed workspace workflow changes.
- Do not provision or perform live window verification without Brian's separate approval.

---

### Task 1: Shared workspace assignment manifest

**Files:**
- Create: `roles/macos/files/omniwm-workspace-rules.json`
- Modify: `roles/macos/files/configure-omniwm-settings`
- Modify: `tests/configure-omniwm-settings.rb`

**Interfaces:**
- Consumes: `configure-omniwm-settings SETTINGS [--rules PATH] [--activate-assignments] [--check]`
- Produces: JSON array entries with `bundleId`, optional `titleRegex`, and `workspace`; reconciled OmniWM `appRules` with the same selectors and `assignToWorkspace` values.

- [ ] **Step 1: Write failing behavioral tests for the manifest-backed rules**

Extend `tests/configure-omniwm-settings.rb` so its helper always supplies the repository manifest through `--rules`. Test active reconciliation twice and parse each resulting app-rule block. Assert these exact assignments:

```ruby
{
  ["com.todoist.mac.Todoist", nil] => "1",
  ["com.apple.Safari", "^Personal —"] => "2",
  ["com.mitchellh.ghostty", nil] => "3",
  ["com.apple.Safari", "^Development —"] => "3",
  ["com.openai.codex", nil] => "4",
  ["com.google.Chrome", nil] => "4",
  ["com.brave.Browser", nil] => "5",
  ["com.getcardpointers.app", nil] => "5",
  ["com.apple.MobileSMS", nil] => "6",
  ["io.robbie.HomeAssistant", nil] => "7",
  ["com.apple.iCal", nil] => "8",
  ["com.apple.Safari", "^Work —"] => "9",
  ["com.tinyspeck.slackmacgap", nil] => "9",
  ["com.bitwarden.desktop", nil] => "10",
  ["com.TechSmith.Snagit", nil] => "10",
  ["com.backblaze.Backblaze", nil] => "10",
  ["com.apple.mobilephone", nil] => "10"
}
```

Also test that active reconciliation removes the superseded managed Chrome rule with `titleSubstring = "ChatGPT"` and Brave rule with `titleSubstring = "Parental Controls"`, preserves unrelated custom rules, excludes Finder and Photos, rejects malformed manifest JSON, rejects unknown keys, rejects missing selectors, rejects invalid workspaces, rejects duplicate entries, and leaves the settings file byte-for-byte unchanged on each manifest error.

- [ ] **Step 2: Run the focused test and confirm the intended failure**

Run:

```bash
ruby tests/configure-omniwm-settings.rb
```

Expected: FAIL because `--rules` and the new manifest do not exist.

- [ ] **Step 3: Add the manifest and manifest parser**

Create `roles/macos/files/omniwm-workspace-rules.json` with the exact table above. Update `configure-omniwm-settings` to:

- parse `--rules PATH` without making option order significant;
- default to `omniwm-workspace-rules.json` beside the script for repository tests;
- parse JSON before changing the settings document;
- require a top-level array of objects;
- permit only `bundleId`, `titleRegex`, and `workspace`;
- require nonempty string values;
- require workspace strings `1` through `10`;
- reject duplicate selector pairs;
- convert entries to `RuleTarget` objects;
- keep floating-only and dynamic Finder/Photos rule definitions in Ruby;
- treat old narrow Chrome and Brave selectors as managed legacy rules and remove their assignment effects during migration;
- preserve all unrelated rule actions and existing atomic-write safeguards.

- [ ] **Step 4: Run focused tests and syntax checks**

Run:

```bash
ruby -c roles/macos/files/configure-omniwm-settings
ruby -rjson -e 'JSON.parse(File.read(ARGV.fetch(0)))' \
  roles/macos/files/omniwm-workspace-rules.json
ruby tests/configure-omniwm-settings.rb
```

Expected: syntax checks succeed and all tests pass.

- [ ] **Step 5: Commit the manifest slice**

Run:

```bash
git add roles/macos/files/omniwm-workspace-rules.json \
  roles/macos/files/configure-omniwm-settings \
  tests/configure-omniwm-settings.rb
git commit -m "Define stable OmniWM workspace rules"
```

---

### Task 2: Bounded login recovery helper

**Files:**
- Create: `roles/macos/files/recover-omniwm-workspaces`
- Create: `tests/recover-omniwm-workspaces.rb`

**Interfaces:**
- Consumes: `recover-omniwm-workspaces [--check] [--rules PATH]`; JSON from `omniwmctl query windows --format json`; the Task 1 manifest.
- Produces: exact calls `omniwmctl rule apply --window OPAQUE_ID`; a text summary and log lines that contain IDs, bundles, profile markers, and workspace numbers but no tab URLs.
- Test controls: `OMNIWMCTL`, `OMNIWM_RECOVERY_LOCK`, `OMNIWM_RECOVERY_MIN_WAIT_SECONDS`, `OMNIWM_RECOVERY_STABLE_SECONDS`, `OMNIWM_RECOVERY_POLL_SECONDS`, `OMNIWM_RECOVERY_TIMEOUT_SECONDS`, and `OMNIWM_RECOVERY_NOTIFY=0`.

- [ ] **Step 1: Write failing end-to-end helper tests**

Create a Minitest suite that executes the production helper with a temporary fake `omniwmctl`. The fake command records arguments and returns scripted ping and window-query JSON. Cover:

- ping retries before success;
- the minimum wait and stable-signature gate with zero-duration test controls;
- exact unique matches for bundle-only rules;
- exact unique Safari matches for `^Personal —`, `^Development —`, and `^Work —`;
- no apply call for unknown, titleless Safari, and a deliberately ambiguous manifest;
- no apply call in `--check` mode while drift is reported;
- no apply call for an already-correct unique match;
- exact `rule apply --window` arguments for a drifted unique match;
- one failed apply is reported without a fallback move and later windows continue;
- malformed query JSON and IPC timeout fail without apply calls;
- a held lock makes a concurrent invocation exit successfully without queries;
- a second normal run over corrected state is idempotent.

Use fake OmniWM IDs such as `ow_test_personal`. Do not duplicate the production classifier in expected-value helper code; assert observable calls and output.

- [ ] **Step 2: Run the helper test and confirm the intended failure**

Run:

```bash
ruby tests/recover-omniwm-workspaces.rb
```

Expected: FAIL because the production helper does not exist.

- [ ] **Step 3: Implement the Ruby recovery helper**

Create an executable Ruby script using only the standard library. Implement:

```ruby
RecoveryRule = Data.define(:bundle_id, :title_regex, :workspace)
Window = Data.define(:id, :bundle_id, :title, :workspace)
```

On Ruby versions without `Data`, use immutable `Struct` definitions. The helper must:

- load and validate the Task 1 manifest with the same field constraints;
- use `flock(File::LOCK_EX | File::LOCK_NB)` on the configured lock path;
- use argv arrays through `Open3.capture3`, never shell command strings;
- wait for `ping` and then for the bounded stability condition;
- derive the stability signature from sorted tuples of ID, bundle ID, title, and workspace;
- classify by exact bundle ID and optional Ruby regular expression;
- skip unless exactly one manifest entry matches;
- skip when the current workspace already equals the target;
- print intended moves in `--check` without calling `rule apply`;
- call `rule apply --window ID` in normal mode and continue after a per-window failure;
- query final state and report observed workspace changes;
- avoid printing page URLs or the full title after classification;
- send one bounded `/usr/bin/osascript display notification` unless notifications are disabled;
- return nonzero for invalid input, readiness timeout, malformed query data, or final query failure;
- return success when individual window operations fail after reporting them;
- always release the lock at exit.

- [ ] **Step 4: Run helper tests and syntax checks**

Run:

```bash
ruby -c roles/macos/files/recover-omniwm-workspaces
ruby tests/recover-omniwm-workspaces.rb
```

Expected: syntax succeeds and all behavioral tests pass.

- [ ] **Step 5: Commit the recovery helper**

Run:

```bash
git add roles/macos/files/recover-omniwm-workspaces \
  tests/recover-omniwm-workspaces.rb
git commit -m "Recover OmniWM workspaces after login"
```

---

### Task 3: Host-gated provisioning and user documentation

**Files:**
- Create: `roles/macos/templates/launchd/com.user.omniwm-workspace-recovery.plist`
- Modify: `roles/macos/tasks/install_omniwm.yml`
- Modify: `.github/workflows/integration-test.yml`
- Modify: `docs/omniwm-cheatsheet.md`

**Interfaces:**
- Consumes: the Task 1 manifest and Task 2 helper.
- Produces: `~/.local/share/omniwm/omniwm-workspace-rules.json`, `~/.local/bin/recover-omniwm-workspaces`, and `~/Library/LaunchAgents/com.user.omniwm-workspace-recovery.plist` only through the exact-host-gated OmniWM task include.

- [ ] **Step 1: Add the host-gated installation wiring**

In `roles/macos/tasks/install_omniwm.yml`, before any settings reconciliation:

- ensure `~/.local/share/omniwm` exists with mode `0755`;
- copy the manifest there with mode `0644`;
- pass `--rules ~/.local/share/omniwm/omniwm-workspace-rules.json` to both prelaunch and normal settings reconciler calls;
- install the recovery helper in `~/.local/bin` with mode `0755`;
- render the recovery LaunchAgent plist with mode `0644`.

The plist must use these values:

```xml
<key>Label</key>
<string>com.user.omniwm-workspace-recovery</string>
<key>ProgramArguments</key>
<array>
  <string>{{ ansible_facts["user_dir"] }}/.local/bin/recover-omniwm-workspaces</string>
  <string>--rules</string>
  <string>{{ ansible_facts["user_dir"] }}/.local/share/omniwm/omniwm-workspace-rules.json</string>
</array>
<key>RunAtLoad</key>
<true/>
```

Set standard output and error paths under
`~/.local/state/omniwm/workspace-recovery.log`. Do not add any launchctl command,
handler, notify action, or changed-result action for this plist. Retain the
existing host gate in `roles/macos/tasks/main.yml` unchanged.

- [ ] **Step 2: Update the cheat sheet**

Add a short “After login” section to `docs/omniwm-cheatsheet.md`. State that the
one-shot helper waits for restored windows and reapplies only unique managed
rules. State that unknown windows remain in place. Document:

```text
recover-omniwm-workspaces --check
recover-omniwm-workspaces
```

Explain that the first command is read-only and the second command can move
uniquely classified windows. Document the Safari profile mapping and the manual
Capital One Shopping Chrome exception.

- [ ] **Step 3: Add the behavioral helper test to pull-request CI**

Add one workflow step after OmniWM settings reconciliation:

```yaml
- name: Verify OmniWM login workspace recovery
  run: ruby tests/recover-omniwm-workspaces.rb
```

Do not add static plist or source-text assertion tests.

- [ ] **Step 4: Run complete targeted verification**

Run:

```bash
ruby tests/configure-omniwm-settings.rb
ruby tests/recover-omniwm-workspaces.rb
ruby -c roles/macos/files/configure-omniwm-settings
ruby -c roles/macos/files/recover-omniwm-workspaces
ansible-playbook playbook.yml --syntax-check
ruby -rrexml/document -e \
  'text=File.read(ARGV.fetch(0)).gsub(/\{\{.*?\}\}/,"/tmp/test"); REXML::Document.new(text)' \
  roles/macos/templates/launchd/com.user.omniwm-workspace-recovery.plist
git diff --check
```

Expected: all commands succeed. Do not run `bin/provision` in this task.

- [ ] **Step 5: Commit provisioning and documentation**

Run:

```bash
git add roles/macos/templates/launchd/com.user.omniwm-workspace-recovery.plist \
  roles/macos/tasks/install_omniwm.yml \
  .github/workflows/integration-test.yml \
  docs/omniwm-cheatsheet.md
git commit -m "Provision OmniWM login recovery"
```

- [ ] **Step 6: Confirm branch state without live side effects**

Run:

```bash
git status --short
git diff --check
git log --oneline origin/main..HEAD
```

Expected: the worktree is clean, the diff check succeeds, and the branch shows
the design, plan, rules, helper, tests, wiring, and documentation commits. No
live windows have moved.
