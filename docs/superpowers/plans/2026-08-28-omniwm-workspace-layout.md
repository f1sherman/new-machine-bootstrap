# OmniWM Workspace Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provision a ten-workspace OmniWM layout on `brian-macbook-pro`, add Finder and Photos pull-up shortcuts, route Ghostty links to a dedicated Safari window, and migrate the current windows without incorrect moves.

**Architecture:** A Ruby reconciler applies narrow, atomic changes to OmniWM's user-generated TOML configuration. A laptop-specific Hammerspoon module uses OmniWM IPC for dynamic Finder, Photos, workspace 10, and URL-routing behavior. A guarded live migration uses exact window IDs and state polling after provisioning succeeds.

**Tech Stack:** Ansible, Ruby 3 with Minitest, Lua with Hammerspoon APIs, OmniWM IPC, macOS AppleScript

**Spec:** `docs/superpowers/specs/2026-08-28-omniwm-workspace-layout-design.md`

## Global Constraints

- Apply the layout only on `brian-macbook-pro` through the existing exact-host OmniWM include.
- Preserve unrelated OmniWM settings and application rules.
- Keep every workspace display label numeric.
- Keep `Option+Shift+Arrow` available for standard macOS text selection.
- Do not assign Apple TV to a workspace.
- Do not infer arbitrary shopping Chrome windows.
- Do not move an ambiguous live window.
- Do not edit deployed files directly; apply source changes with `bin/provision`.

---

### Task 1: Atomic OmniWM Settings Reconciler

**Files:**
- Create: `roles/macos/files/configure-omniwm-settings`
- Create: `tests/configure-omniwm-settings.rb`

**Interfaces:**
- Consumes: `configure-omniwm-settings SETTINGS_PATH`
- Produces: Exit 0 with `changed` or `unchanged` on stdout; exit nonzero without replacing the source file on invalid input.
- Produces: Workspaces 1-10, required hotkeys, and safe application assignments in the input TOML.

- [ ] **Step 1: Write failing fixture-based tests**

Create `tests/configure-omniwm-settings.rb` with Minitest cases that copy a representative settings document into a temporary directory and execute the production helper with `Open3.capture3`.

The fixture must contain:

```toml
[general]
ipcEnabled = true

[[appRules]]
bundleId = "com.mitchellh.ghostty"
id = "ghostty-rule"
minHeight = 400.0

[[appRules]]
bundleId = "user.unrelated"
id = "unrelated-rule"
layout = "float"

[[hotkeys]]
binding = "Option+1"
id = "switchWorkspace.0"

[[hotkeys]]
binding = "Option+Shift+Left Arrow"
id = "move.left"

[[hotkeys]]
binding = "Control+Option+T"
id = "toggleScratchpadWindow"

[[workspaces]]
id = "workspace-1"
layoutType = "niri"
name = "1"

[workspaces.monitorAssignment]
type = "main"
```

Tests must assert:

```ruby
assert status.success?, err
assert_equal "changed\n", out
assert_includes result, 'name = "10"'
assert_includes result, 'binding = "Unassigned"\nid = "move.left"'
assert_includes result, 'assignToWorkspace = "3"'
assert_includes result, 'bundleId = "user.unrelated"'
assert_includes result, 'minHeight = 400.0'
```

Add separate cases for a byte-for-byte idempotent second run, no duplicate app rules, workspaces 8-10 added once, all optional `displayName` lines removed, and malformed input left unchanged.

- [ ] **Step 2: Run the focused test and confirm failure**

Run:

```bash
ruby tests/configure-omniwm-settings.rb
```

Expected: FAIL because `roles/macos/files/configure-omniwm-settings` does not exist.

- [ ] **Step 3: Implement the reconciler**

Create an executable Ruby script with these focused units:

```ruby
Workspace = Struct.new(:name, :id, :monitor, keyword_init: true)
RuleTarget = Struct.new(:bundle_id, :title_substring, :workspace, keyword_init: true)

ADDED_WORKSPACES = [
  Workspace.new(name: "8", id: "4371F67B-B469-470D-89C6-D8FBB5E65BD3", monitor: "main"),
  Workspace.new(name: "9", id: "E9D12AB0-EB5E-4B50-98BC-600318BA00FC", monitor: "main"),
  Workspace.new(name: "10", id: "1935F5A8-9DCA-4E80-AEE3-48EBBE2E336A", monitor: "main")
].freeze

RULE_TARGETS = [
  RuleTarget.new(bundle_id: "com.todoist.mac.Todoist", workspace: "1"),
  RuleTarget.new(bundle_id: "com.mitchellh.ghostty", workspace: "3"),
  RuleTarget.new(bundle_id: "com.openai.codex", workspace: "4"),
  RuleTarget.new(bundle_id: "com.google.Chrome", title_substring: "ChatGPT", workspace: "4"),
  RuleTarget.new(bundle_id: "com.getcardpointers.app", workspace: "5"),
  RuleTarget.new(bundle_id: "com.brave.Browser", title_substring: "Parental Controls", workspace: "5"),
  RuleTarget.new(bundle_id: "com.apple.MobileSMS", workspace: "6"),
  RuleTarget.new(bundle_id: "io.robbie.HomeAssistant", workspace: "7"),
  RuleTarget.new(bundle_id: "com.apple.iCal", workspace: "8"),
  RuleTarget.new(bundle_id: "com.tinyspeck.slackmacgap", workspace: "9"),
  RuleTarget.new(bundle_id: "com.apple.Safari", title_substring: "Work —", workspace: "9"),
  RuleTarget.new(bundle_id: "com.bitwarden.desktop", workspace: "10"),
  RuleTarget.new(bundle_id: "com.TechSmith.Snagit", workspace: "10"),
  RuleTarget.new(bundle_id: "com.backblaze.Backblaze", workspace: "10"),
  RuleTarget.new(bundle_id: "com.apple.mobilephone", workspace: "10"),
  RuleTarget.new(bundle_id: "com.apple.finder", workspace: "10"),
  RuleTarget.new(bundle_id: "com.apple.Photos", workspace: "10")
].freeze
```

Use the exact `bundleId`, `titleSubstring`, and `assignToWorkspace` keys emitted by OmniWM v0.6.3. Match a title-specific rule on both bundle ID and title so it cannot affect another application. Reuse existing workspace IDs for names 1-7. Use the fixed UUID-format IDs above for missing workspaces 8-10 and preserve an existing ID when the named workspace is already present.

Parse the TOML as ordered top-level scalar lines and repeated `[[hotkeys]]`, `[[appRules]]`, and `[[workspaces]]` blocks. Update a matching block in place and retain unknown lines. Add a missing rule at the end of the app-rule group. Set the workspace action key without removing size or layout actions.

Before replacement:

1. Require `[general]`, at least one hotkey block, and at least one workspace block.
2. Reparse the generated text with the same structural parser.
3. Write to a sibling temporary file with mode 0600.
4. Rename the temporary file over the source atomically.
5. Print `unchanged` without writing when bytes are equal.

- [ ] **Step 4: Run the reconciler tests**

Run:

```bash
ruby tests/configure-omniwm-settings.rb
```

Expected: all tests pass with zero failures and zero errors.

- [ ] **Step 5: Commit the reconciler**

```bash
~/.pi/agent/skills/z-commit/commit.sh \
  -m "Manage OmniWM workspace settings" \
  roles/macos/files/configure-omniwm-settings \
  tests/configure-omniwm-settings.rb
```

### Task 2: Hammerspoon OmniWM Helpers

**Files:**
- Create: `roles/macos/files/hammerspoon/omniwm.lua`

**Interfaces:**
- Consumes: `~/.local/bin/omniwmctl`, Hammerspoon `hs.task`, `hs.json`, `hs.hotkey`, `hs.urlevent`, `hs.application`, and `hs.osascript`.
- Produces: `Control+Option+D`, `Control+Option+P`, `Option+0`, and `Option+Shift+0` global shortcuts.
- Produces: `hs.urlevent.httpCallback` with normal Safari fallback.

- [ ] **Step 1: Record live IPC contracts before coding**

Run and save the relevant field names in working notes:

```bash
omniwmctl query active-workspace --format json
omniwmctl query windows --format json
omniwmctl query windows --scratchpad --format json
omniwmctl query capabilities --format json
```

Confirm the exact JSON paths for window ID, PID, bundle ID, workspace number,
visibility, and scratchpad state. Confirm `window summon-right`, `window
navigate`, `command scratchpad assign`, `command scratchpad toggle`, `command
switch-workspace`, and `command move-to-workspace` are present.

- [ ] **Step 2: Implement asynchronous OmniWM primitives**

Create `roles/macos/files/hammerspoon/omniwm.lua` with a private module table and these interfaces:

```lua
local M = {}
local omniwmctl = os.getenv("HOME") .. "/.local/bin/omniwmctl"

function M.run(args, callback) end
function M.query(args, callback) end
function M.poll(predicate, timeoutSeconds, callback) end
function M.activeWorkspace(callback) end
function M.windows(callback) end
function M.notify(message) end
```

`M.run` must use `hs.task.new` without blocking Hammerspoon. `M.query` must decode JSON with `pcall(hs.json.decode, stdout)` and return an error on nonzero exit or malformed JSON. `M.poll` must use `hs.timer.doUntil` with a 0.1-second interval and a bounded timeout. Every callback must return either `(result, nil)` or `(nil, errorMessage)`.

- [ ] **Step 3: Implement Finder and Photos actions**

Implement:

```lua
function M.toggleDownloadsScratchpad() end
function M.togglePhotos() end
```

Finder flow:

1. Query the scratchpad.
2. Toggle when its bundle ID is `com.apple.finder`.
3. Notify and stop when another bundle owns it.
4. When absent, use AppleScript to create a Finder window whose target is
   `POSIX file "$HOME/Downloads"`.
5. Diff the Finder window IDs before and after creation.
6. Navigate to the exact new ID, poll focus, assign it, and toggle only when the
   resulting state requires it.

Photos flow:

1. Query active workspace and Photos windows.
2. Launch Photos when no window exists, then discover its exact new ID.
3. If its workspace equals the active workspace, navigate and move it to 10.
4. Otherwise summon it to the right of the focused window.
5. Poll the exact ID until the destination matches.

Never select the first arbitrary window after a timeout.

- [ ] **Step 4: Implement workspace 10 and URL routing**

Bind:

```lua
hs.hotkey.bind({"alt"}, "0", function()
  M.run({"command", "switch-workspace", "10"}, M.reportResult)
end)

hs.hotkey.bind({"alt", "shift"}, "0", function()
  M.run({"command", "move-to-workspace", "10"}, M.reportResult)
end)
```

Set `hs.urlevent.httpCallback` with the documented five-argument signature.
Resolve the sender with `hs.application.applicationForPID(senderPID)`.

For non-Ghostty senders, call:

```lua
hs.urlevent.openURLWithBundle(fullURL, "com.apple.Safari")
```

For `com.mitchellh.ghostty`, resolve the dedicated Safari window from a validated
`hs.settings` hint or a Safari window in workspace 3 that is not a Work window.
Summon it to the active workspace, poll its exact ID, navigate to it, and use
AppleScript to create a new tab with `fullURL`. On any failure, notify and call
the normal Safari forwarding path.

Call `hs.urlevent.setDefaultHandler("http")` only when
`hs.urlevent.getDefaultHandler("http")` is not Hammerspoon. Before that call,
store the previous bundle identifier in `hs.settings` and pass it to
`hs.urlevent.setRestoreHandler("http", previousBundleID)` so rollback can
restore the prior handler.

- [ ] **Step 5: Validate Lua syntax without changing live state**

Run:

```bash
luac -p roles/macos/files/hammerspoon/omniwm.lua
```

Expected: exit 0 and no output. This is a syntax check only; live behavioral verification remains in Task 4.

- [ ] **Step 6: Commit Hammerspoon helpers**

```bash
~/.pi/agent/skills/z-commit/commit.sh \
  -m "Add OmniWM pull-up shortcuts" \
  roles/macos/files/hammerspoon/omniwm.lua
```

### Task 3: Provision the Managed Configuration

**Files:**
- Modify: `roles/macos/tasks/install_omniwm.yml`

**Interfaces:**
- Consumes: Task 1 reconciler and Task 2 Hammerspoon file.
- Produces: Updated `~/.config/omniwm/settings.toml` and laptop-specific `~/.hammerspoon/init.local.lua` through Ansible.

- [ ] **Step 1: Replace ad hoc TOML edits with the reconciler**

In `roles/macos/tasks/install_omniwm.yml`, keep the settings-file wait and stat tasks. Replace the numeric-label and hotkey `lineinfile`/`replace` tasks with:

```yaml
- name: Configure OmniWM workspace layout
  script:
    cmd: >-
      configure-omniwm-settings
      {{ ansible_facts['user_dir'] }}/.config/omniwm/settings.toml
  register: omniwm_settings_result
  changed_when: omniwm_settings_result.stdout | trim == 'changed'
  when: omniwm_settings_file.stat.exists
```

Keep IPC enabled before the reconciler or make IPC one of the reconciler's
required scalar values. Do not run the reconciler when the settings file is
absent.

- [ ] **Step 2: Install the laptop-specific Hammerspoon file**

Add tasks inside the already host-gated OmniWM include:

```yaml
- name: Ensure Hammerspoon configuration directory exists
  file:
    path: "{{ ansible_facts['user_dir'] }}/.hammerspoon"
    state: directory
    mode: '0755'

- name: Install OmniWM Hammerspoon helpers
  copy:
    src: hammerspoon/omniwm.lua
    dest: "{{ ansible_facts['user_dir'] }}/.hammerspoon/init.local.lua"
    mode: '0644'
  register: omniwm_hammerspoon_config
```

The existing generic Hammerspoon task later in the role loads
`init.local.lua` and reloads Hammerspoon. Do not add a second reload path unless
live verification proves the existing order is insufficient.

- [ ] **Step 3: Run static verification**

Run:

```bash
ansible-playbook playbook.yml --syntax-check
ruby tests/configure-omniwm-settings.rb
luac -p roles/macos/files/hammerspoon/omniwm.lua
git diff --check
```

Expected: every command exits 0.

- [ ] **Step 4: Commit provisioning integration**

```bash
~/.pi/agent/skills/z-commit/commit.sh \
  -m "Provision OmniWM workspace layout" \
  roles/macos/tasks/install_omniwm.yml
```

### Task 4: Deploy, Verify, and Migrate Live Windows

**Files:**
- No repository file changes expected.
- Create temporary evidence only under `/tmp`; do not commit it.

**Interfaces:**
- Consumes: Provisioned settings and Hammerspoon helpers from Tasks 1-3.
- Produces: Ten live workspaces and the approved current-window placement.

- [ ] **Step 1: Save the pre-migration snapshot**

Run:

```bash
omniwmctl query windows --format json \
  > /tmp/omniwm-windows-before-layout.json
omniwmctl query workspaces --format json \
  > /tmp/omniwm-workspaces-before-layout.json
```

Validate both files with `ruby -rjson -e 'JSON.parse(File.read(ARGV[0]))' FILE`.
Do not move a window before both snapshots parse.

- [ ] **Step 2: Provision the branch**

Run:

```bash
bin/provision
```

Expected: exit 0; the settings reconciler reports `changed`; Hammerspoon reloads;
OmniWM IPC verification returns `pong`. Brian must approve the macOS prompt that
sets Hammerspoon as the HTTP and HTTPS handler.

- [ ] **Step 3: Verify configuration before migration**

Run:

```bash
omniwmctl ping
omniwmctl query workspaces --format table
omniwmctl query rules --format table
```

Expected: workspaces 1-10 have numeric labels and safe rules match the approved
mapping. Inspect `~/.config/omniwm/settings.toml` read-only to confirm
`Option+Shift+Arrow` remains unassigned.

- [ ] **Step 4: Move windows with an exact-ID migration program**

Run a temporary Ruby program from `/tmp` that reads the saved snapshot and builds
only these matches:

```ruby
targets = {
  ["com.todoist.mac.Todoist", nil] => 1,
  ["com.mitchellh.ghostty", nil] => 3,
  ["com.openai.codex", nil] => 4,
  ["com.getcardpointers.app", nil] => 5,
  ["com.apple.MobileSMS", nil] => 6,
  ["io.robbie.HomeAssistant", nil] => 7,
  ["com.apple.iCal", nil] => 8,
  ["com.tinyspeck.slackmacgap", nil] => 9,
  ["com.bitwarden.desktop", nil] => 10,
  ["com.TechSmith.Snagit", nil] => 10,
  ["com.backblaze.Backblaze", nil] => 10,
  ["com.apple.mobilephone", nil] => 10
}
```

Add exact-title predicates for the approved current Safari, Chrome, Brave, and
shopping windows from the snapshot. Do not use a broad Safari or Chrome fallback.

For every move:

1. Requery the exact ID and skip it if absent.
2. Switch to its recorded current workspace.
3. Run `window navigate ID`.
4. Poll `query focused-window` until the ID matches.
5. Run `command move-to-workspace N`.
6. Poll `query windows --window ID` until workspace N matches.
7. Stop and record a failure rather than continue after focus or move timeout.

Move Todoist out of the scratchpad before assigning Finder. Create the dedicated
Downloads Finder through the deployed Hammerspoon action only after all ordinary
moves succeed. Close Apple TV by bundle identifier after the placement checks.

- [ ] **Step 5: Verify pull-up and browser behavior end to end**

Manually verify:

1. `Control+Option+D` creates and toggles a Downloads Finder window.
2. A second Finder toggle hides the same exact scratchpad window.
3. `Control+Option+P` summons Photos from Parking to the current workspace.
4. A second Photos toggle returns the same window to workspace 10.
5. A Ghostty link opens as a new tab in the dedicated Safari window in Ghostty's
   workspace.
6. A link from a non-Ghostty application opens through normal Safari handling.
7. `Option+0` switches to Parking.
8. `Option+Shift+0` moves a disposable test window to Parking.
9. `Option+Shift+Left/Right` still selects text by word.

Restore the disposable test window after step 8.

- [ ] **Step 6: Verify final layout and idempotency**

Run:

```bash
omniwmctl query windows --format json \
  > /tmp/omniwm-windows-after-layout.json
omniwmctl query workspaces --format table
bin/provision --check
ruby tests/configure-omniwm-settings.rb
```

Compare the final JSON with the workspace table in the spec. Confirm ambiguous
and auxiliary windows were not moved. Expected: no failed checks; the reconciler
test remains idempotent; check mode reports no OmniWM settings drift.

- [ ] **Step 7: Final branch verification**

Run:

```bash
ansible-playbook playbook.yml --syntax-check
ruby tests/configure-omniwm-settings.rb
luac -p roles/macos/files/hammerspoon/omniwm.lua
git diff --check main..HEAD
git status --short
```

Expected: every verification exits 0 and the worktree is clean.
