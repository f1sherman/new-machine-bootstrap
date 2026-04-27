# `cldr` — resume the Claude session bound to this tmux pane

**Date:** 2026-04-27
**Status:** Approved
**Repo:** `new-machine-bootstrap`

## Goal

Provide a short command, `cldr`, that resumes "the Claude session that was running in this tmux pane." Brian commonly runs multiple Claude sessions in parallel across different tmux panes in the same project directory, so the existing `claude --continue` behavior (most-recently-modified session in cwd) is not specific enough — it can resume the wrong pane's session.

The name `cldr` (rather than the more obvious `cr`) avoids ambiguity with anything Codex-flavored. `cld` is the natural short form of "Claude" already in use elsewhere in this repo's tooling.

## Approach

Use the `SessionStart` hook from this repo's `tmux-recovery-hardening` work, which writes the active session's UUID to a tmux pane option (`@persist_claude_session_id`) on startup. `cldr` reads that option from the current pane and resumes the matching session. If the option is unset (no tmux, hook not yet installed, or no claude has ever run in this pane) `cldr` falls back to `claude --continue` so it is always at least as good as the status quo.

This approach was chosen over alternatives:

- **Wrap the start command** — would require swapping the `claude-yolo` shell alias for a script. Rejected because the SessionStart hook covers every entry point (yolo alias, IDE integration, `--worktree`, `--from-pr`, future entry points) without us having to remember to use the wrapper.
- **Scrollback scan** — fragile, depends on Claude printing the session ID and on the buffer not having rolled.
- **Manual fallback only (`claude -c`)** — does not solve the multi-pane problem.

## Dependency

The `@persist_claude_session_id` option is set by `tmux-claude-session-start`, a `SessionStart` hook designed in `.coding-agent/plans/2026-04-27-tmux-recovery-hardening.md` (Task 6, in the `tmux-recovery-hardening` worktree). That plan owns the hook script and its registration in `~/.claude/settings.json`. This spec intentionally does not duplicate either; until the recovery plan lands, `cldr` falls back to `claude -c`.

The two pieces of work are separable:

- If `tmux-recovery-hardening` lands first, `cldr` is fully deterministic from day one.
- If `cldr` lands first, it behaves like `claude -c` until the hook is installed, then automatically gains the per-pane behavior with no code change.

## File structure

| Action | Path | Responsibility |
|---|---|---|
| Create | `roles/common/files/bin/cldr` | The script. |
| Modify | `roles/common/tasks/main.yml` | Install task that copies `cldr` to `~/.local/bin/cldr`. |

No documentation update is required: there is no existing per-script index in this repo's `CLAUDE.md` or `README.md` to keep in sync.

## Script behavior

```bash
#!/usr/bin/env bash
# cldr — resume the Claude session bound to this tmux pane.
#
# Reads the pane option @persist_claude_session_id (set by the SessionStart
# hook from the tmux-recovery-hardening work). If absent, falls back to
# `claude --continue` (most recent session in cwd).
set -u

session_id=""
if [ -n "${TMUX_PANE:-}" ]; then
  session_id=$(tmux show-options -pqv -t "$TMUX_PANE" @persist_claude_session_id 2>/dev/null || true)
fi

if [ -n "$session_id" ]; then
  exec claude --dangerously-skip-permissions --resume "$session_id" "$@"
else
  exec claude --dangerously-skip-permissions --continue "$@"
fi
```

Notes on the implementation:

- `exec` replaces the shell so Claude takes over the pane cleanly — signals and exit codes pass through with no extra layer.
- `"$@"` is forwarded, so ad-hoc overrides like `cldr --model opus` work.
- `tmux show-options` flags: `-p` pane scope, `-q` quiet on missing option, `-v` value-only (no `name=` prefix).
- `--dangerously-skip-permissions` matches the existing `claude-yolo` shell alias — this is the user's standard interactive mode.
- `set -u` (without `-e`): the `tmux show-options` call uses `|| true` to absorb a nonzero exit when the option is unset, and `set -e` would short-circuit that.

## Provisioning

Add a new task to `roles/common/tasks/main.yml`, placed alongside the other "Install X script" copy tasks (current cluster begins around line 124 with `git-diff-untracked`, `pick-files`, `osc52-copy`, etc.):

```yaml
- name: Install cldr script
  copy:
    src: '{{ playbook_dir }}/roles/common/files/bin/cldr'
    dest: '{{ ansible_facts["user_dir"] }}/.local/bin/cldr'
    mode: '0755'
```

Exact insertion point is left to the implementer; pick whichever spot keeps the file's organization consistent.

## Testing

No automated test — the script is ten lines of glue to two CLIs (`claude`, `tmux`). Manual verification:

1. `bin/provision` installs `cldr`.
2. In a tmux pane, run `claude --dangerously-skip-permissions`, send a prompt, exit.
3. Run `cldr` in the same pane → resumes that session.
4. Open a second tmux pane in the same directory, start a different Claude session, exit.
5. Back in pane 1, run `cldr` → resumes pane 1's session, not pane 2's. (Requires the recovery plan's `SessionStart` hook to be installed; without it, this step falls back to `-c` and resumes whichever was most recent.)
6. Run `cldr` in a non-tmux terminal → falls back to `claude -c`.
7. Run `cldr` in a fresh tmux pane that has never run Claude → falls back to `claude -c`.
8. Run `cldr --model opus` in a pane with a stored session id → resumes with the model override applied.

## Edge cases

| Scenario | Behavior |
|---|---|
| Outside tmux (`$TMUX_PANE` unset) | Falls back to `claude -c`. |
| Inside tmux but `@persist_claude_session_id` unset | Falls back to `claude -c`. |
| Stored session id no longer has a session file (e.g. cleaned up) | `claude --resume` errors clearly; not handled here. |
| Extra args passed to `cldr` | Forwarded to `claude` via `"$@"`. |

## Non-goals

- Globally finding the latest session across all directories.
- Interactive picker over multiple sessions — that is `claude -r`.
- Any pane→session tracking mechanism owned by this spec. The mapping lives in tmux pane options, written by the hook from `tmux-recovery-hardening`.
- Replacing the `claude-yolo` alias with a wrapper.

## Known limitation

Until `tmux-recovery-hardening` lands, parallel Claude sessions in the same directory still collapse to "most recently modified" via the `-c` fallback. `cldr` does not make this worse than the status quo, and gains the desired per-pane behavior automatically once the hook is installed.
