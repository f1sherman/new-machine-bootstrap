# Codex Hooks Trusted Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automatically trust the Codex hooks provisioned by `new-machine-bootstrap` without trusting unrelated user hooks.

**Architecture:** Add one installed helper that asks Codex for normalized hook metadata, filters it against an explicit managed-hook manifest, and writes matching `trusted_hash` entries into `~/.codex/config.toml`. Wire that helper into `roles/common/tasks/main.yml` after all managed `hooks.json` merge tasks, then cover the trust updater with a focused shell test and CI workflow entry.

**Tech Stack:** Bash, `jq`, Ruby for TOML-preserving text updates, Ansible, existing repo shell test style.

---

## File Structure

- Create `roles/common/files/bin/codex-trust-managed-hooks`: command-line helper. Reads Codex hook metadata from Codex app-server or `CODEX_HOOK_METADATA_FILE`, filters managed hooks, updates `config.toml`, prints `changed` or `unchanged`.
- Create `tests/codex-hook-trust.sh`: focused regression test for managed hook trust, idempotence, unrelated hook preservation, hash refresh, and stale-key cleanup.
- Modify `roles/common/tasks/main.yml`: install the helper and run it after the managed Codex hook merge tasks.
- Modify `.github/workflows/integration-test.yml`: run `tests/codex-hook-trust.sh` so `tests/ci-test-inventory.sh` stays green.

## Task 1: Failing Trust Updater Test

**Files:**
- Create: `tests/codex-hook-trust.sh`
- Modify: `.github/workflows/integration-test.yml`

- [ ] **Step 1: Create the failing test file**

Create `tests/codex-hook-trust.sh` as an executable Bash test:

```bash
#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(git -C "$script_dir" rev-parse --show-toplevel)"
helper="$repo_root/roles/common/files/bin/codex-trust-managed-hooks"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

pass_case() { printf 'PASS  %s\n' "$1"; }
fail_case() { printf 'FAIL  %s\n%s\n' "$1" "$2" >&2; exit 1; }

assert_file_contains() {
  local path="$1" needle="$2" name="$3"
  if ! rg -F -- "$needle" "$path" >/dev/null 2>&1; then
    fail_case "$name" "missing '$needle' in $path"
  fi
  pass_case "$name"
}

assert_file_not_contains() {
  local path="$1" needle="$2" name="$3"
  if rg -F -- "$needle" "$path" >/dev/null 2>&1; then
    fail_case "$name" "unexpected '$needle' in $path"
  fi
  pass_case "$name"
}

assert_equals() {
  local actual="$1" expected="$2" name="$3"
  if [ "$actual" != "$expected" ]; then
    fail_case "$name" "expected '$expected', got '$actual'"
  fi
  pass_case "$name"
}

assert_mode_600() {
  local path="$1" name="$2" mode
  mode="$(stat -c '%a' "$path" 2>/dev/null || stat -f '%Lp' "$path")"
  assert_equals "$mode" "600" "$name"
}

write_metadata() {
  local path="$1" workdir="$2" hooks_file="$3" work_hash="$4" push_hash="$5" user_hash="$6"
  jq -n \
    --arg cwd "$workdir" \
    --arg hooks "$hooks_file" \
    --arg workHash "$work_hash" \
    --arg pushHash "$push_hash" \
    --arg userHash "$user_hash" \
    '{
      data: [
        {
          cwd: $cwd,
          warnings: [],
          errors: [],
          hooks: [
            {
              key: ($hooks + ":pre_tool_use:0:0"),
              eventName: "preToolUse",
              handlerType: "command",
              matcher: "Bash",
              command: "~/.local/bin/codex-block-worktree-commands",
              timeoutSec: 600,
              statusMessage: null,
              sourcePath: $hooks,
              source: "user",
              pluginId: null,
              displayOrder: 0,
              enabled: true,
              isManaged: false,
              currentHash: $workHash,
              trustStatus: "untrusted"
            },
            {
              key: ($hooks + ":pre_tool_use:1:0"),
              eventName: "preToolUse",
              handlerType: "command",
              matcher: "Bash",
              command: "~/.local/bin/codex-block-git-push-main",
              timeoutSec: 600,
              statusMessage: null,
              sourcePath: $hooks,
              source: "user",
              pluginId: null,
              displayOrder: 1,
              enabled: true,
              isManaged: false,
              currentHash: $pushHash,
              trustStatus: "untrusted"
            },
            {
              key: ($hooks + ":pre_tool_use:2:0"),
              eventName: "preToolUse",
              handlerType: "command",
              matcher: "Bash",
              command: "~/.local/bin/user-hook",
              timeoutSec: 600,
              statusMessage: null,
              sourcePath: $hooks,
              source: "user",
              pluginId: null,
              displayOrder: 2,
              enabled: true,
              isManaged: false,
              currentHash: $userHash,
              trustStatus: "untrusted"
            }
          ]
        }
      ]
    }' >"$path"
}

if [ ! -x "$helper" ]; then
  fail_case "helper exists and is executable" "missing executable: $helper"
fi
pass_case "helper exists and is executable"

codex_home="$tmpdir/codex"
mkdir -p "$codex_home"
hooks_file="$codex_home/hooks.json"
config_file="$codex_home/config.toml"
metadata_file="$tmpdir/hooks-metadata.json"

cat >"$hooks_file" <<JSON
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "~/.local/bin/codex-block-worktree-commands"
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "~/.local/bin/codex-block-git-push-main"
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "~/.local/bin/user-hook"
          }
        ]
      }
    ]
  }
}
JSON

cat >"$config_file" <<TOML
model = "gpt-5.5"

[hooks.state."$hooks_file:pre_tool_use:99:0"]
trusted_hash = "sha256:stale"

[hooks.state."/other/hooks.json:pre_tool_use:0:0"]
trusted_hash = "sha256:keep"
TOML

write_metadata "$metadata_file" "$tmpdir/work" "$hooks_file" "sha256:work-v1" "sha256:push-v1" "sha256:user-v1"

out="$(
  CODEX_HOME="$codex_home" \
  HOOKS_FILE="$hooks_file" \
  CONFIG_FILE="$config_file" \
  CODEX_HOOK_METADATA_FILE="$metadata_file" \
    "$helper"
)"
assert_equals "$out" "changed" "first run reports changed"
assert_file_contains "$config_file" "[hooks.state.\"$hooks_file:pre_tool_use:0:0\"]" "worktree hook state section is written"
assert_file_contains "$config_file" 'trusted_hash = "sha256:work-v1"' "worktree hook hash is trusted"
assert_file_contains "$config_file" "[hooks.state.\"$hooks_file:pre_tool_use:1:0\"]" "push hook state section is written"
assert_file_contains "$config_file" 'trusted_hash = "sha256:push-v1"' "push hook hash is trusted"
assert_file_not_contains "$config_file" "sha256:user-v1" "unrelated user hook is not auto-trusted"
assert_file_not_contains "$config_file" "$hooks_file:pre_tool_use:99:0" "stale state for same hooks file is removed"
assert_file_contains "$config_file" "/other/hooks.json:pre_tool_use:0:0" "unrelated hook state is preserved"
assert_mode_600 "$config_file" "config file mode is 0600"

out="$(
  CODEX_HOME="$codex_home" \
  HOOKS_FILE="$hooks_file" \
  CONFIG_FILE="$config_file" \
  CODEX_HOOK_METADATA_FILE="$metadata_file" \
    "$helper"
)"
assert_equals "$out" "unchanged" "second run reports unchanged"

write_metadata "$metadata_file" "$tmpdir/work" "$hooks_file" "sha256:work-v2" "sha256:push-v1" "sha256:user-v2"
out="$(
  CODEX_HOME="$codex_home" \
  HOOKS_FILE="$hooks_file" \
  CONFIG_FILE="$config_file" \
  CODEX_HOOK_METADATA_FILE="$metadata_file" \
    "$helper"
)"
assert_equals "$out" "changed" "hash drift reports changed"
assert_file_contains "$config_file" 'trusted_hash = "sha256:work-v2"' "changed managed hash is refreshed"
assert_file_not_contains "$config_file" "sha256:work-v1" "old managed hash is removed"
assert_file_not_contains "$config_file" "sha256:user-v2" "changed unrelated user hook is still not trusted"

printf 'codex-hook-trust checks complete\n'
```

- [ ] **Step 2: Add the test to CI workflow**

Add this step after `Verify Codex SessionStart hook contract` in `.github/workflows/integration-test.yml`:

```yaml
      - name: Verify Codex hook trust provisioning
        run: bash tests/codex-hook-trust.sh
```

- [ ] **Step 3: Run the new test and confirm Red**

Run:

```bash
bash tests/codex-hook-trust.sh
```

Expected: FAIL with `missing executable: .../roles/common/files/bin/codex-trust-managed-hooks`.

- [ ] **Step 4: Commit the failing test**

Run:

```bash
~/.codex/skills/_commit/commit.sh -m "Add Codex hook trust regression test" \
  tests/codex-hook-trust.sh \
  .github/workflows/integration-test.yml
```

## Task 2: Trust Updater Helper

**Files:**
- Create: `roles/common/files/bin/codex-trust-managed-hooks`

- [ ] **Step 1: Create the helper script**

Create `roles/common/files/bin/codex-trust-managed-hooks` executable. The implementation must include these concrete behaviors:

```bash
#!/usr/bin/env bash
set -euo pipefail

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
HOOKS_FILE="${HOOKS_FILE:-$CODEX_HOME/hooks.json}"
CONFIG_FILE="${CONFIG_FILE:-$CODEX_HOME/config.toml}"
CODEX_BIN="${CODEX_BIN:-codex}"
QUERY_CWD="${CODEX_HOOK_QUERY_CWD:-$PWD}"

require_command() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    printf 'missing required command: %s\n' "$name" >&2
    exit 1
  fi
}

managed_manifest() {
  jq -n '[
    {eventName:"preToolUse", matcher:"Bash", command:"~/.local/bin/codex-block-worktree-commands", timeoutSec:600},
    {eventName:"preToolUse", matcher:"Bash", command:"~/.local/bin/codex-block-git-push-main", timeoutSec:600},
    {eventName:"preToolUse", matcher:"apply_patch|Edit|Write", command:"~/.local/bin/codex-block-main-branch-edits", timeoutSec:600},
    {eventName:"postToolUse", matcher:"apply_patch|Edit|Write", command:"~/.local/bin/agent-current-spec-hook", timeoutSec:600},
    {eventName:"sessionStart", matcher:"startup|resume", command:"~/.local/bin/codex-bind-tmux-pane", timeoutSec:5},
    {eventName:"userPromptSubmit", matcher:null, command:"~/.local/bin/codex-remind-repo-start-on-dev-prompt", timeoutSec:600}
  ]'
}

read_response_by_id() {
  local fd="$1" id="$2" line
  while IFS= read -r -t 20 -u "$fd" line; do
    if printf '%s' "$line" | jq -e --argjson id "$id" '.id == $id' >/dev/null 2>&1; then
      printf '%s\n' "$line"
      return 0
    fi
  done
  printf 'timed out waiting for Codex app-server response id %s\n' "$id" >&2
  return 1
}

fetch_metadata() {
  if [[ -n "${CODEX_HOOK_METADATA_FILE:-}" ]]; then
    cat "$CODEX_HOOK_METADATA_FILE"
    return 0
  fi

  require_command "$CODEX_BIN"
  local init_request list_request init_response list_response
  init_request="$(jq -nc '{id:1, method:"initialize", params:{clientInfo:{name:"nmb-hook-trust", title:null, version:"0"}, capabilities:{experimentalApi:true}}}')"
  list_request="$(jq -nc --arg cwd "$QUERY_CWD" '{id:2, method:"hooks/list", params:{cwds:[$cwd]}}')"

  coproc CODEX_SERVER { "$CODEX_BIN" app-server --listen stdio://; }
  trap 'kill "$CODEX_SERVER_PID" >/dev/null 2>&1 || true' RETURN

  printf '%s\n' "$init_request" >&"${CODEX_SERVER[1]}"
  init_response="$(read_response_by_id "${CODEX_SERVER[0]}" 1)"
  printf '%s\n' "$init_response" | jq -e '.result.codexHome' >/dev/null

  printf '%s\n' '{"method":"initialized"}' >&"${CODEX_SERVER[1]}"
  printf '%s\n' "$list_request" >&"${CODEX_SERVER[1]}"
  list_response="$(read_response_by_id "${CODEX_SERVER[0]}" 2)"
  printf '%s\n' "$list_response" | jq -c '.result'
}

build_trust_plan() {
  local metadata="$1" manifest="$2"
  jq -c --arg hooks_file "$HOOKS_FILE" --argjson manifest "$manifest" '
    def norm_timeout: (.timeoutSec // 600 | tonumber);
    .data[0] as $entry
    | if (($entry.warnings // []) | length) > 0 then
        error("Codex hooks/list returned warnings: " + (($entry.warnings // []) | join("; ")))
      elif (($entry.errors // []) | length) > 0 then
        error("Codex hooks/list returned errors: " + (($entry.errors // [] | map(.message // tostring)) | join("; ")))
      else
        {
          current_keys: [($entry.hooks // [])[] | select(.sourcePath == $hooks_file) | .key],
          managed: [
            $manifest[] as $managed
            | [($entry.hooks // [])[] | select(
                .source == "user"
                and .sourcePath == $hooks_file
                and .eventName == $managed.eventName
                and .matcher == $managed.matcher
                and .command == $managed.command
                and (norm_timeout == $managed.timeoutSec)
              )] as $matches
            | if ($matches | length) != 1 then
                error("expected exactly one managed hook match for " + $managed.command)
              else
                $matches[0] | {key, currentHash, command}
              end
          ]
        }
      end
  ' <<<"$metadata"
}

update_config() {
  local plan_json="$1" pairs_file current_keys_file
  pairs_file="$(mktemp)"
  current_keys_file="$(mktemp)"
  trap 'rm -f "$pairs_file" "$current_keys_file"' RETURN

  jq -r '.managed[] | [.key, .currentHash] | @tsv' <<<"$plan_json" >"$pairs_file"
  jq -r '.current_keys[]' <<<"$plan_json" >"$current_keys_file"

  PAIRS_FILE="$pairs_file" \
  CURRENT_KEYS_FILE="$current_keys_file" \
  CONFIG_FILE="$CONFIG_FILE" \
  HOOKS_FILE="$HOOKS_FILE" \
  ruby <<'RUBY'
require "fileutils"

config_file = ENV.fetch("CONFIG_FILE")
hooks_file = ENV.fetch("HOOKS_FILE")
pairs = File.readlines(ENV.fetch("PAIRS_FILE"), chomp: true).map { |line| line.split("\t", 2) }.to_h
current_keys = File.readlines(ENV.fetch("CURRENT_KEYS_FILE"), chomp: true).to_h { |key| [key, true] }
text = File.exist?(config_file) ? File.read(config_file) : ""
lines = text.lines(chomp: true)
state_section = /^\[hooks\.state\."([^"]+)"\]\s*(?:[#;].*)?$/
any_section = /^\[[^\]]+\]\s*(?:[#;].*)?$/

output = []
index = 0

while index < lines.length
  line = lines[index]
  match = line.match(state_section)

  unless match
    output << line
    index += 1
    next
  end

  key = match[1]
  section_lines = [line]
  index += 1
  while index < lines.length && lines[index] !~ any_section
    section_lines << lines[index]
    index += 1
  end

  next if pairs.key?(key)
  next if key.start_with?("#{hooks_file}:") && !current_keys.key?(key)

  output.concat(section_lines)
end

output << "" unless output.empty? || output[-1] == ""
pairs.each do |key, hash|
  output << %([hooks.state."#{key}"])
  output << %(trusted_hash = "#{hash}")
  output << ""
end
output.pop if output[-1] == ""

new_text = output.empty? ? "" : "#{output.join("\n")}\n"
if new_text != text
  FileUtils.mkdir_p(File.dirname(config_file))
  File.write(config_file, new_text)
  File.chmod(0o600, config_file)
  puts "changed"
else
  File.chmod(0o600, config_file) if File.exist?(config_file)
  puts "unchanged"
end
RUBY
}

require_command jq
require_command ruby

metadata="$(fetch_metadata)"
manifest="$(managed_manifest)"
plan_json="$(build_trust_plan "$metadata" "$manifest")"
update_config "$plan_json"
```

After writing the file, run:

```bash
chmod +x roles/common/files/bin/codex-trust-managed-hooks
```

- [ ] **Step 2: Run the focused test and confirm Green**

Run:

```bash
bash tests/codex-hook-trust.sh
```

Expected: output ends with `codex-hook-trust checks complete`.

- [ ] **Step 3: Commit the helper**

Run:

```bash
~/.codex/skills/_commit/commit.sh -m "Trust managed Codex hook hashes" \
  roles/common/files/bin/codex-trust-managed-hooks
```

## Task 3: Provisioning Wiring

**Files:**
- Modify: `roles/common/tasks/main.yml`
- Modify: `tests/repo-policy.sh`

- [ ] **Step 1: Add helper to install loop**

In `roles/common/tasks/main.yml`, add this entry to the `Install worktree helpers` loop after `codex-bind-tmux-pane`:

```yaml
    - { name: codex-trust-managed-hooks, mode: '0755' }
```

- [ ] **Step 2: Add the Ansible trust task**

In `roles/common/tasks/main.yml`, add this task after `Merge managed Codex repo-start prompt hook into ~/.codex/hooks.json` and before `Enforce 0600 on ~/.codex/hooks.json`:

```yaml
- name: Trust managed Codex hooks in ~/.codex/config.toml
  command: '{{ ansible_facts["user_dir"] }}/.local/bin/codex-trust-managed-hooks'
  environment:
    CODEX_HOME: '{{ ansible_facts["user_dir"] }}/.codex'
    HOOKS_FILE: '{{ ansible_facts["user_dir"] }}/.codex/hooks.json'
    CONFIG_FILE: '{{ ansible_facts["user_dir"] }}/.codex/config.toml'
    CODEX_HOOK_QUERY_CWD: '{{ playbook_dir }}'
  register: codex_trust_managed_hooks_result
  changed_when: codex_trust_managed_hooks_result.stdout.strip() == 'changed'
```

- [ ] **Step 3: Add repo policy assertions**

In `tests/repo-policy.sh`, add this variable near the other Codex hook variables:

```bash
CODEX_TRUST_MANAGED_HOOKS="$REPO_ROOT/roles/common/files/bin/codex-trust-managed-hooks"
```

In `run_install_checks`, add these assertions near the other Codex provisioning assertions:

```bash
  assert_contains "$COMMON_MAIN" "- { name: codex-trust-managed-hooks, mode: '0755' }" "common install loop includes Codex hook trust helper"
  assert_contains "$COMMON_MAIN" "Trust managed Codex hooks in ~/.codex/config.toml" "common provisioning trusts managed Codex hooks"
  assert_contains "$COMMON_MAIN" "CODEX_HOOK_QUERY_CWD: '{{ playbook_dir }}'" "Codex hook trust task queries hooks for the playbook directory"
  assert_contains "$CODEX_TRUST_MANAGED_HOOKS" "codex-block-worktree-commands" "Codex trust helper manifest includes worktree hook"
  assert_contains "$CODEX_TRUST_MANAGED_HOOKS" "codex-remind-repo-start-on-dev-prompt" "Codex trust helper manifest includes repo-start prompt hook"
```

- [ ] **Step 4: Run policy and trust tests**

Run:

```bash
bash tests/codex-hook-trust.sh
bash tests/repo-policy.sh installs
```

Expected: both pass with `0 failed`.

- [ ] **Step 5: Commit provisioning wiring**

Run:

```bash
~/.codex/skills/_commit/commit.sh -m "Provision trusted Codex hook state" \
  roles/common/tasks/main.yml \
  tests/repo-policy.sh
```

## Task 4: Verification And PR

**Files:**
- No production file changes expected.

- [ ] **Step 1: Run focused tests**

Run:

```bash
bash tests/codex-hook-trust.sh
bash tests/repo-policy.sh installs
bash tests/ci-test-inventory.sh
```

Expected: every command exits 0.

- [ ] **Step 2: Run broader repository policy tests**

Run:

```bash
bash tests/repo-policy.sh all
```

Expected: exits 0 with `0 failed`.

- [ ] **Step 3: Run provisioning check**

Run:

```bash
bin/provision --check
```

Expected: exits 0. If Ansible reports check-mode limitations from Codex app-server startup, run `bin/provision` and record the reason.

- [ ] **Step 4: Empirical managed hook trust verification**

Run:

```bash
bin/provision
```

Then query Codex metadata from this repo:

```bash
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
codex app-server generate-json-schema --out "$tmp/schema" >/dev/null
```

Start a short `codex app-server --listen stdio://` session and send:

```json
{"id":1,"method":"initialize","params":{"clientInfo":{"name":"nmb-verify","title":null,"version":"0"},"capabilities":{"experimentalApi":true}}}
{"method":"initialized"}
{"id":2,"method":"hooks/list","params":{"cwds":["/Users/brian/projects/new-machine-bootstrap/.worktrees/codex-hooks-trusted"]}}
```

Expected: all six managed hooks report `trustStatus: "trusted"` and any unrelated user hook does not become trusted unless it was already trusted.

- [ ] **Step 5: Create PR**

After verification passes, invoke the repo PR workflow:

```bash
create-pull-request
```
