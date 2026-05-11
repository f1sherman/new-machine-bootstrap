# tmux window label refresh on Claude/Codex resume — Design

## Goal

When a Claude Code or Codex CLI session resumes inside a tmux pane (e.g. `claude --resume <id>`, `claude --continue`, `cldr`, `cdxr`, or a tmux-resurrect restore that re-launches an agent), refresh the pane's cached `@pane-label` and rename the enclosing tmux window so the status bar reflects the current pane state.

## Non-goals

- Changing the existing pane-label content. Agent panes labelled by `tmux-agent-worktree` (`repo (branch)`) stay that way; non-agent panes keep the `cwd | host` fallback.
- Refreshing window names for non-resume agent activity (e.g. every prompt). The pane-title OSC sequences emitted by `claude-working-on.sh` already drive the `pane-title-changed` path; we do not duplicate that.
- Renaming the tmux session, the Ghostty tab title, or the pane border format. Those have their own owners.
- Reconciling stale window names left behind by `tmux-resurrect` restore in the general case. That is a separate gap and handled out of scope (see "Out of scope / related" below).
- Adding a new manual command. `prefix L` already exists for forced refreshes.

## Assumptions

- `tmux-window-label` and `tmux-update-pane-label` are the canonical writers of window names and `@pane-label`, respectively. They are idempotent and safe to call any time a pane is alive in tmux.
- Both helpers short-circuit when `@agent_worktree_path` is set: `tmux-update-pane-label` exits without touching the cache, and `tmux-window-label` reads the cached `@pane-label` instead of recomputing. The combined call therefore preserves the `repo (branch)` label written by `repo-start` / `tmux-agent-worktree`.
- Claude SessionStart fires for fresh startups, `--resume`, `/clear`, and `/compact`. `tmux-claude-session-start` is already the single Claude SessionStart hook that has both `TMUX_PANE` and the agent payload.
- Codex SessionStart matcher `startup|resume` fires `codex-bind-tmux-pane`. We treat startup and resume the same: refresh on both.
- The Claude SessionStart hook receives a `source` field; `"resume"`, `"clear"`, `"compact"`, and the default startup case are all states where a label refresh is correct.
- Nested `claude -p` invocations (subagents) hit the same SessionStart hook. The existing nested-call short-circuit in `tmux-claude-session-start` is the right gate: when the hook bails to preserve the outer pane's session id, the label refresh should also be skipped.
- `tmux-window-label` and `tmux-update-pane-label` running concurrently from other hooks (e.g. `pane-focus-in`) is already safe; adding one more call site doesn't change that.

## Background

Today the window-name pipeline is event-driven:

| Trigger | Calls |
|---|---|
| `pane-focus-in`, `client-session-changed` | `tmux-window-label`, `tmux-update-pane-label` |
| `pane-title-changed` | `tmux-pane-title-changed` → `tmux-update-pane-label` |
| `after-split-window`, `after-new-window`, `after-new-session`, `window-linked` | `tmux-update-pane-label` |
| zsh `chpwd` | `tmux-window-label`, `tmux-sync-pane-border-status` |
| `prefix L` | `tmux-update-all-pane-labels` |

The gap: resuming an agent CLI in the same pane changes nothing tmux observes directly. The pane's `pane_current_command` may already be `claude` or `codex` (or `zsh`, if the user runs `cldr` from a shell prompt), `pane_current_path` doesn't change, and the pane title only updates if the agent emits an OSC sequence. So the window name keeps whatever value it had before the resume — which in practice is often a previous repo's basename, a stale `cwd | host`, or a tmux-resurrect-restored leftover.

The SessionStart hooks already run on every agent resume, already know `TMUX_PANE`, and already write per-pane options. They are the natural place to fire a label refresh.

## Recommended approach — extend the existing SessionStart hooks

Add a single trailing call into `tmux-claude-session-start` and `codex-bind-tmux-pane` that refreshes both the cached `@pane-label` and the window name for the current pane.

Concretely, at the end of each script — after the existing `tmux set-option` calls that write the session-id state — invoke:

```
"$HOME/.local/bin/tmux-update-pane-label" "$TMUX_PANE" >/dev/null 2>&1 || true
"$HOME/.local/bin/tmux-window-label"      "$TMUX_PANE" >/dev/null 2>&1 || true
```

Order matters: `tmux-update-pane-label` must run first so `tmux-window-label`'s `@pane-label` read sees the fresh value (or, for agent worktrees, sees the unchanged `repo (branch)` cache). Both calls swallow failure to preserve the existing "hooks must never break the agent" contract.

In `tmux-claude-session-start`, the refresh goes after the `tmux set-option ... @persist_claude_session_id` line and inherits the script's existing nested-call short-circuit (no refresh when the outer pane's session id is preserved).

In `codex-bind-tmux-pane`, the refresh goes after the three `tmux set-option ... @codex_session_*` lines and runs on both `startup` and `resume` matcher hits, matching today's behavior.

### Why this approach

- **Minimal surface area.** Two small additions inside files we already manage; no new scripts, no new ansible tasks, no new tmux hooks.
- **Correctness by construction.** `tmux-update-pane-label` already does the right thing for agent vs. non-agent panes via its `@agent_worktree_path` short-circuit. `tmux-window-label` is the same script every other refresh path calls.
- **Reuses the existing failure contract.** The SessionStart hooks already exit 0 on any error so the agent never breaks. The label calls inherit that.
- **No race with other refresh paths.** Adding one more invocation of an idempotent script does not change behavior when other hooks also fire.

### Tradeoffs

- The refresh runs once per SessionStart (startup, resume, clear, compact). On every startup, the existing `after-new-window`/`after-split-window`/`after-new-session`/`window-linked` hooks already updated the cache, so the SessionStart refresh is mostly redundant on cold start — but cheap, and it covers the resume case which today is not covered at all.
- If the SessionStart hook itself fails (timeout, missing `jq`, etc.), the label refresh also doesn't happen. That's the same failure mode as the rest of the hook and is acceptable for a cosmetic refresh.
- For the nested `claude -p` path, the label refresh deliberately does not fire. That is the correct behavior — the outer pane's label is still right, and refreshing on every subagent shell-out would be wasted work.

## Alternatives considered

### Alternative A — dedicated `tmux-agent-session-label-refresh` script registered as a separate SessionStart hook

Add a tiny new script that invokes the two label helpers and register it as an additional SessionStart entry in `~/.claude/settings.json` and `~/.codex/hooks.json`. Each existing hook keeps a single responsibility (session-id capture).

Cleaner separation, but it requires:

- A new file in `roles/common/files/bin/`.
- A new ansible block in `roles/common/tasks/main.yml` that idempotently merges the entry into both settings files (mirroring the two existing merge blocks).
- Two SessionStart entries fire per resume instead of one, which is fine but doubles the per-resume hook fork count.

The cost (new script, new ansible config, more JSON merging) is disproportionate to the value (separation of concerns for two trivial lines). Rejected.

### Alternative B — fire only on `source=resume`

Inside the Claude hook, only refresh when `source` is `resume` (and inside the Codex hook, only when matcher hit is `resume`, which would require a different matcher split). The argument is that fresh startups are already covered by `after-new-pane`/`window-linked`.

Two problems:

1. The Codex hook's matcher is a single `startup|resume` regex; splitting it adds maintenance for no real benefit because the refresh is cheap.
2. There are edge cases where startup also needs the refresh — e.g. a tmux-resurrect restore that recreates the pane with a stale saved `window_name`. The `window-linked` hook only refreshes `@pane-label`; it does not call `tmux-window-label`, so the stale window name persists until something else (e.g. focus-in) fires. Running the full refresh on every SessionStart catches this.

Rejected — the savings are not worth the extra branching.

### Alternative C — drive label refresh from `claude-working-on.sh` / a Notification hook

Refresh the window name whenever Claude pings (e.g. start of work, prompt submit). This would catch resume but also catch many other events.

This re-renames the window on every Claude turn, fights with the user's manual `tmux rename-window`, and produces a lot of cheap-but-noisy `set-option` traffic. Rejected.

## Architecture and components

```
SessionStart event (Claude or Codex)
        │
        ▼
~/.claude/settings.json       ~/.codex/hooks.json
       │                              │
       ▼                              ▼
tmux-claude-session-start     codex-bind-tmux-pane
       │                              │
       │  (existing) set @persist_claude_session_id
       │  (existing) set @codex_session_id/_cwd/_transcript
       │                              │
       ▼                              ▼
       └──────────── new ─────────────┘
                       │
                       ▼
          tmux-update-pane-label "$TMUX_PANE"
                       │
                       ▼
              tmux-window-label "$TMUX_PANE"
                       │
                       ▼
                tmux rename-window
```

### Files touched

| File | Change |
|---|---|
| `roles/common/files/bin/tmux-claude-session-start` | After the existing `@persist_claude_session_id` set-option, append the two label-refresh invocations. |
| `roles/common/files/bin/codex-bind-tmux-pane` | After the three `@codex_session_*` set-option calls, append the two label-refresh invocations. |
| `tests/` | New test (or extension of `tmux-label-contract.sh`) that drives the two hooks and asserts the window gets renamed. |

No changes to ansible tasks, tmux.conf, settings.json templates, or any other file.

### Boundaries

- `tmux-claude-session-start` and `codex-bind-tmux-pane` remain SessionStart hooks. They do not gain new responsibilities beyond "after I write session state, refresh the visible label."
- `tmux-update-pane-label` and `tmux-window-label` are unchanged.
- The repo-lifecycle owner of `@pane-label` for agent panes (`tmux-agent-worktree`) remains authoritative; the new calls cannot overwrite its cached value because of the existing `@agent_worktree_path` short-circuit in `tmux-update-pane-label`.

## Error handling

- Both label helpers are invoked with `|| true` and stderr discarded; failures are swallowed.
- If `TMUX_PANE` is unset the hook exits earlier; the new calls never run.
- If the pane has been killed between the agent emitting the SessionStart event and the hook running, the helpers' own `tmux display-message` calls return empty and they exit 0.
- If neither helper is on `$PATH` (e.g. fresh machine pre-provision), the `|| true` keeps the SessionStart hook successful and the agent continues uninterrupted.

## Testing and verification plan

### Local manual

1. In a tmux pane, run `claude` (fresh start). Confirm window name matches the existing pane label.
2. Detach Claude (`/exit`). Rename the window manually to something junk: `tmux rename-window junk`.
3. Run `claude --continue` (or `cldr`). Confirm the window name is restored to the pane label within a second of the agent resuming.
4. Repeat with `codex` and `cdxr`.
5. From a repo pane that has run `repo-start`, run `claude --continue`. Confirm the window name is the `repo (branch)` form, not the cwd basename, and that `@pane-label` is unchanged.

### Automated

Add a test that:

1. Spawns a tmux server, opens a pane, sets a known `window_name`.
2. Pipes a synthetic SessionStart JSON payload (`{"session_id":"x","source":"resume"}`) to `tmux-claude-session-start` with `TMUX_PANE` set to the pane id.
3. Asserts `window_name` was renamed to the expected pane-label.
4. Repeats with `codex-bind-tmux-pane` and a synthetic payload `{"session_id":"x","cwd":"/tmp","transcript_path":"/tmp/t"}`.
5. Sets `@agent_worktree_path` and `@pane-label` before the run; asserts the cached `@pane-label` is preserved and the window is renamed to it.

This fits into the existing `tests/tmux-label-contract.sh` style. If the existing harness already has a tmux fixture, extend it rather than introduce a parallel harness.

## Rollout

Single commit on a worktree branch, PR, merge. No migration required: the change is additive and silent — the only visible effect is that previously-stale window names become correct again.

## Out of scope / related

- **tmux-resurrect restore window-name staleness.** When the tmux server restarts, `tmux-update-all-pane-labels` refreshes `@pane-label` for every pane but never renames windows. The SessionStart-based refresh covers panes that re-launch an agent on restore (because `@resurrect-processes` includes `claude --continue`), but pure-shell panes are unaffected. A complementary fix would extend `tmux-update-all-pane-labels` to also call `tmux-window-label` per pane. Tracked as a separate concern.
- **Resume detection for `cldr`/`cdxr`.** Both wrappers ultimately exec the agent CLI which fires SessionStart, so this design covers them transitively without dedicated wiring.
