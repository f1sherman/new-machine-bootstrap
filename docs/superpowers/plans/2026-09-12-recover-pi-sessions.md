# Recover Pi Sessions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Include standard and nested Pi JSONL sessions in the generic recent-session recovery helper.

**Architecture:** Read Pi session JSONL files directly and convert them to the helper's existing normalized read-data shape. Recursively enumerate the configured Pi session root, validate each authoritative header, and send valid entries through the existing summary and rendering pipeline.

**Tech Stack:** Ruby, JSONL, shell-level end-to-end fixture verification

**Spec:** `docs/superpowers/specs/2026-09-12-recover-pi-sessions-design.md`

## Global Constraints

- Do not depend on HNP, Herdr, or ASR.
- Resume Pi by exact JSONL file path.
- Ignore malformed files and symlink aliases.
- Keep transcript collections bounded.
- Update the common and Pi-specific recovery skill descriptions.

---

### Task 1: Discover and Normalize Pi Sessions

**Files:**
- Modify: `roles/common/files/bin/_recover-agent-sessions`

**Interfaces:**
- Produces: `read_pi_session(file)` with `session_id`, `cwd`, `name`, `user_messages`, `assistant_messages`, and `shell_commands`.
- Produces: `list_pi_sessions(root, start_epoch, end_epoch)` entries compatible with `build_session_hash`.
- Extends: `build_resume_command(tool, cwd, session_id, file)` for tool `Pi`.

- [ ] **Step 1: Build a temporary fixture and confirm Pi is absent**

Create a temporary HOME with one valid standard Pi JSONL file and one valid
nested Pi JSONL file. Run:

```bash
HOME="$fixture_home" \
RECOVER_AGENT_SESSIONS_CODEX_BIN=/missing/codex \
roles/common/files/bin/_recover-agent-sessions 24h --json
```

Expected: output is `[]` because Pi is not implemented.

- [ ] **Step 2: Add Pi message extraction**

Implement `pi_text_from_message(message)` for string and text-array content.
Implement `read_pi_session(file)` so the first row must be a `session` row with
non-empty `id` and absolute `cwd`. For later rows:

- retain the latest `session_info.name`;
- retain bounded user and assistant message text;
- retain bounded `bash` tool-call command arguments.

Return an empty hash for malformed or unreadable input.

- [ ] **Step 3: Add recursive discovery**

Implement `list_pi_sessions(root, start_epoch, end_epoch)` with `Find.find`.
Accept only regular `.jsonl` files whose real path equals their path and whose
mtime is in the requested window. Normalize each valid file into an entry for
`build_session_hash`.

- [ ] **Step 4: Add exact-path Pi resume commands**

Extend `build_resume_command` to return:

```ruby
%(cd "#{quoted_cwd}" && pi --session "#{shell_double_quote(file)}")
```

for Pi. Pass `file` from `build_session_hash`.

- [ ] **Step 5: Add Pi entries to the main pipeline**

Use `RECOVER_AGENT_SESSIONS_PI_SESSION_DIR` for explicit recovery-root
overrides, then `PI_CODING_AGENT_SESSION_DIR`, then the `sessions` directory
under `PI_CODING_AGENT_DIR`, then `~/.pi/agent/sessions`. Append valid Pi
entries before sorting and summary hydration.

- [ ] **Step 6: Verify the fixtures**

Run the fixture command again. Expected:

- both valid Pi IDs appear;
- the newer file appears first;
- each resume command contains its exact file path;
- malformed, symlinked, and stale fixtures do not appear.

- [ ] **Step 7: Syntax-check the helper**

Run:

```bash
ruby -c roles/common/files/bin/_recover-agent-sessions
```

Expected: `Syntax OK`.

### Task 2: Update Recovery Skill Guidance

**Files:**
- Modify: `roles/common/files/config/skills/common/_recover-agent-sessions/SKILL.md`
- Modify: `roles/common/files/config/skills/pi/z-recover-agent-sessions/SKILL.md`

**Interfaces:**
- Produces: guidance that the helper finds Claude, Codex, and Pi sessions and
  that Pi resume commands use exact session files.

- [ ] **Step 1: Update both descriptions and command rules**

Add Pi to the session types. State that generated Pi resume commands use
`pi --session <exact-jsonl-path>`.

- [ ] **Step 2: Inspect the complete diff**

Run:

```bash
git diff --check
git diff
```

Expected: no whitespace errors and no HNP-specific dependency.

### Task 3: Verify and Commit

**Files:**
- Modify: all files from Tasks 1 and 2.

**Interfaces:**
- Consumes: the complete Pi recovery implementation.
- Produces: committed, provisionable recovery support.

- [ ] **Step 1: Run the repository test command for the helper if present**

Search the repository for retained tests that execute `_recover-agent-sessions`.
Run any matching test. Do not add a static configuration-presence test.

- [ ] **Step 2: Verify against the real session store**

Run the worktree helper with model summarization disabled and a narrow window
that includes the known OpenClaw session. Confirm session ID
`ad71cad9-ae97-4fd5-b326-3be51704a43e` appears and its resume command contains
the nested legacy path.

- [ ] **Step 3: Commit the implementation**

```bash
bash ~/.local/share/skills/_commit/commit.sh \
  -m "Include Pi in session recovery" \
  roles/common/files/bin/_recover-agent-sessions \
  roles/common/files/config/skills/common/_recover-agent-sessions/SKILL.md \
  roles/common/files/config/skills/pi/z-recover-agent-sessions/SKILL.md
```
