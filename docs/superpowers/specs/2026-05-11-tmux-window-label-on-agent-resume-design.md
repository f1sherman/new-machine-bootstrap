# tmux window label refresh on Claude/Codex resume — Design

## Goal

When a Claude Code or Codex CLI session resumes inside a tmux pane, make the pane's `@pane-label` and the enclosing tmux window's name reflect the active state — including the active *worktree* when the agent is doing worktree-based work. Two distinct cases need to be handled together:

1. **Same-pane resume.** The same pane that originally ran `repo-start` is resumed (typically via `cldr` / `cdxr` / `claude --continue`). `@agent_worktree_path` and the cached `@pane-label` are already set; we just need to re-render the window name in case it got stomped (tmux-resurrect restore, manual `tmux rename-window`, etc.).
2. **Cross-pane resume.** The session is resumed in a *different* pane (e.g. a new window after a terminal restart). The new pane has no `@agent_worktree_path` and tmux cannot recover the worktree on its own (see Background). The agent itself is the only source of truth — so we ask the agent, via an injected system reminder, to republish.

## Non-goals

- Changing the existing pane-label content. Agent panes labelled by `tmux-agent-worktree` (`(branch) repo | host`) stay that way; non-agent panes keep the `cwd | host` fallback.
- Refreshing window names for non-resume agent activity (e.g. every prompt). The pane-title OSC sequences emitted by `claude-working-on.sh` already drive the `pane-title-changed` path; we do not duplicate that.
- Renaming the tmux session, the Ghostty tab title, or the pane border format. Those have their own owners.
- Auto-detecting the worktree from pane state. `pane_current_path` and the Codex SessionStart `cwd` field both report the agent process's *launch directory*, not the active worktree (see Background). The agent is the authority; the hook only nudges.
- Persisting a session-id → worktree-path sidecar. Rejected (see Alternatives).
- Adding a new manual command. `prefix L` already exists for forced refreshes.

## Assumptions

- `tmux-window-label`, `tmux-update-pane-label`, and `tmux-agent-worktree` are the canonical writers of window names and `@pane-label`. They are idempotent and safe to call any time a pane is alive in tmux.
- `tmux-update-pane-label` short-circuits when `@agent_worktree_path` is set; `tmux-window-label` reads the cached `@pane-label` instead of recomputing. The combined call therefore preserves the `(branch) repo` label written by `repo-start` / `tmux-agent-worktree`.
- Claude SessionStart fires for fresh startups, `--resume`, `/clear`, and `/compact`. `tmux-claude-session-start` is the single Claude SessionStart hook that has `TMUX_PANE` and the agent payload.
- Codex SessionStart matcher `startup|resume` fires `codex-bind-tmux-pane`. Codex uses the same hook payload vocabulary as Claude (`startup|resume|clear|compact`), so we treat the hook firings symmetrically. The Part 2 nudge is gated on pane state (`@agent_worktree_path` unset), not on the `source` field, so we don't need to differentiate startup vs resume in either agent.
- Both Claude and Codex hooks support emitting `{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"..."}}` on stdout to inject a system reminder. Working precedents in this repo: `block-initiation-skill-on-main.sh` (Claude PostToolUse), `codex-remind-repo-start-on-dev-prompt` (Codex UserPromptSubmit).
- The agent has its active worktree in conversation history, plan files, or its `.coding-agent/` working state. When prompted on resume, it can determine the correct path and run `tmux-agent-worktree set <path>` itself.
- `tmux-agent-worktree set <path>` is idempotent. It rejects non-worktree paths and refreshes the window label internally, so a misfire is recoverable and a correct call is sufficient.
- Nested `claude -p` invocations (subagents) hit the same SessionStart hook. The existing nested-call short-circuit in `tmux-claude-session-start` is the right gate: when the hook bails to preserve the outer pane's session id, the new behavior (label refresh + nudge) is also skipped.

## Background

### Why pane state can't recover the worktree

Claude and Codex don't chdir when working in a worktree. `repo-start` creates a linked worktree under `.worktrees/<branch>` and writes `@agent_worktree_path = <worktree path>` on the *current pane* via `tmux-agent-worktree set` (see `roles/common/files/bin/repo-start:332` and `roles/common/files/bin/tmux-agent-worktree:203`). It does **not** chdir the agent. The agent process keeps its original cwd (the launch dir / main worktree). Tool calls use `cd <worktree> && ...` in fresh subshells which do not propagate back.

Consequences for the labeler:

- `pane_current_path` (which tmux reads from the foreground process's cwd) reflects the **launch dir**, never the **active worktree**.
- The Codex SessionStart payload field `cwd` is the **session's launch dir**, not the worktree. Same trap.
- The only authoritative source of the active worktree path is the option `@agent_worktree_path`, which exists on a pane only because `repo-start` published it there.

### Why this breaks cross-pane resume

On a same-pane resume the option is still on the pane (tmux options outlive the agent process). On a cross-pane resume (new window, terminal restart attaching to a fresh pane, `cldr`/`cdxr` invoked from a different window) the option doesn't exist on the new pane and no derivation from tmux state can recover it.

### Why label refresh is still needed on SessionStart

Today the window-name pipeline is event-driven:

| Trigger | Calls |
|---|---|
| `pane-focus-in`, `client-session-changed` | `tmux-window-label`, `tmux-update-pane-label` |
| `pane-title-changed` | `tmux-pane-title-changed` → `tmux-update-pane-label` |
| `after-split-window`, `after-new-window`, `after-new-session`, `window-linked` | `tmux-update-pane-label` |
| zsh `chpwd` | `tmux-window-label`, `tmux-sync-pane-border-status` |
| `prefix L` | `tmux-update-all-pane-labels` |

Resuming an agent in the same pane changes nothing tmux observes (no `cd`, no focus event, no new pane, no OSC title until the agent emits one). The cached `@pane-label` is correct but the window name keeps whatever value it had — often a tmux-resurrect-restored leftover, or a manual rename. The SessionStart hook is the natural place to re-render.

## Recommended approach

Two complementary additions, both inside the existing SessionStart hooks. No new scripts, no new ansible tasks, no new tmux hooks, no persistent state.

### Part 1 — refresh the window label on SessionStart

At the end of each script — after the existing `tmux set-option` calls that write the session-id state — invoke:

```
"$HOME/.local/bin/tmux-update-pane-label" "$TMUX_PANE" >/dev/null 2>&1 || true
"$HOME/.local/bin/tmux-window-label"      "$TMUX_PANE" >/dev/null 2>&1 || true
```

Order matters: `tmux-update-pane-label` must run first so `tmux-window-label`'s `@pane-label` read sees the fresh value (or, for agent worktrees, sees the unchanged `(branch) repo` cache). Both calls swallow failure to preserve the existing "hooks must never break the agent" contract.

This fixes the same-pane stale-window-name case.

### Part 2 — nudge the agent to republish worktree state on cross-pane resume

When **all** of the following are true, emit a `hookSpecificOutput.additionalContext` reminder asking the agent to call `tmux-agent-worktree set <path>`:

1. `TMUX_PANE` is set (i.e. we're in a tmux session at all).
2. The pane has no `@agent_worktree_path` set.

We deliberately do **not** gate on the SessionStart `source` (`startup` vs `resume`/`clear`/`compact`). On a true fresh start where the user hasn't yet run `repo-start`, the reminder is harmless: the agent reads it, determines it's not in a worktree workflow, and ignores it. Avoiding the source check keeps the two hook implementations symmetric and removes a payload-shape dependency.

The injected reminder text (one shared message for both agents):

> You are resuming a session in a tmux pane that has no active worktree bound to it. If your prior work in this session was in a git worktree (e.g. a linked worktree under `.worktrees/<branch>`), run `tmux-agent-worktree set <absolute-worktree-path>` so this tmux pane and window reflect the active worktree. Resolve the path from your conversation history, plan files, or `.coding-agent/` state. If this session is not using a worktree, ignore this reminder.

JSON shape (mirrors existing reminder hooks in this repo):

```json
{"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": "<text>"}}
```

When the agent runs `tmux-agent-worktree set <path>`, it:

- Validates `<path>` is a git worktree (refuses otherwise).
- Writes `@agent_worktree_path`, `@agent_worktree_pid`, and `@pane-label` on the pane.
- Calls `refresh_window_label` and `publish_title` internally.

So a single agent action republishes all derived state. No additional refresh from our side is required after the nudge.

### Why this approach

- **Right source of truth.** The agent is the only thing that knows its active worktree. We ask the entity that knows.
- **No persistent state.** No sidecar files, no expiry, no cleanup at `repo-end`.
- **Single writer of `@agent_worktree_path`.** `repo-start` and `tmux-agent-worktree` remain the only writers; the agent invokes them, the hook does not.
- **Minimal surface area.** Two small additions inside two scripts we already manage.
- **Self-correcting.** If the agent picks the wrong worktree, the user can correct it conversationally.
- **No noise in the common case.** The nudge fires only when `@agent_worktree_path` is missing, so same-pane resumes (the majority) pay zero turn cost.

### Tradeoffs

- Cross-pane resume costs ~1 extra turn (agent reads reminder, decides, runs one bash command). Acceptable.
- Fresh starts in a non-worktree pane (where the user hasn't run `repo-start` yet) also receive the reminder. The agent ignores it. Minor noise; trade-off accepted to avoid depending on the `source` field shape across agents.
- The agent may pick the wrong worktree if its history is ambiguous. Recoverable conversationally; not silent.
- Hook output now sometimes contains JSON (Part 2 cases), sometimes nothing (Part 1 cases). Both agents already tolerate this — see existing hooks that emit conditionally.
- If the SessionStart hook itself fails (timeout, missing `jq`, etc.), neither the label refresh nor the nudge happens. Same failure mode as the rest of the hook; acceptable for a cosmetic refresh and an advisory reminder.

## Alternatives considered

### Alternative A — dedicated `tmux-agent-session-label-refresh` script as a separate hook entry

Add a tiny new script that runs both parts and register it as an additional SessionStart entry. Cleaner separation of concerns at the cost of a new script, a new ansible block in `roles/common/tasks/main.yml`, and twice the per-resume hook fork count. Rejected — the cost is disproportionate to the value for two small additions in files we already own.

### Alternative B — fire only on `source=resume`

Restrict Part 1 (label refresh) to resume events only. The argument is that fresh startups are already covered by `after-new-pane`/`window-linked`.

The savings don't justify the branching. Startup also benefits from a refresh in some edge cases (e.g. tmux-resurrect restore that recreated a pane with a saved-but-stale `window_name`; `window-linked` only refreshes `@pane-label`, not the window name itself). Rejected.

### Alternative C — drive label refresh from `claude-working-on.sh` / a Notification hook

Refreshing on every Claude turn fights with manual `tmux rename-window` and produces noisy `set-option` traffic. Rejected.

### Alternative D — persist session-id → worktree-path sidecar

Have `repo-start` write `~/.local/state/agent-worktrees/<session_id>` containing the worktree path; have the SessionStart hook read it on resume and republish without involving the agent.

Rejected:

- Adds a new persistent state file with its own lifecycle (creation, update on `repo-end`, expiry for dead sessions, race with tmux-resurrect restore).
- Introduces a second writer of pane worktree state, weakening the "`repo-start` / `tmux-agent-worktree` is the single writer" invariant.
- Doesn't handle the case where the agent worked in multiple worktrees in one session (only the last one would be in the sidecar).
- The agent already has the answer in its history; storing it twice is duplication that can drift.

### Alternative E — `cldr` / `cdxr` republish before exec

Have the resume wrappers look up the prior worktree state and republish before exec'ing the agent.

Rejected for two reasons:

1. Doesn't cover bare `claude --resume` / `codex resume` invocations.
2. Same "where does the wrapper learn the worktree" problem — would still need a sidecar or some other persistent map. Inherits Alternative D's downsides.

## Architecture

```
SessionStart event (Claude or Codex)
        │
        ▼
~/.claude/settings.json       ~/.codex/hooks.json
       │                              │
       ▼                              ▼
tmux-claude-session-start     codex-bind-tmux-pane
       │                              │
       │  (existing) write session-id state on pane
       │
       ├─── Part 1 (always) ────────────────────────┐
       │                                            │
       │     tmux-update-pane-label "$TMUX_PANE"    │
       │     tmux-window-label "$TMUX_PANE"         │
       │                                            ▼
       │                                     tmux rename-window
       │
       └─── Part 2 (resume AND no @agent_worktree_path) ───┐
                                                           │
              emit hookSpecificOutput.additionalContext   │
                                                           ▼
                              agent runs tmux-agent-worktree set <path>
                                                           │
                                                           ▼
                              writes @agent_worktree_path, @pane-label,
                              refreshes window label, publishes title
```

### Files touched

| File | Change |
|---|---|
| `roles/common/files/bin/tmux-claude-session-start` | After the `@persist_claude_session_id` set-option, run the Part 1 label refresh. Before exiting, if `@agent_worktree_path` is unset on the pane, emit Part 2 JSON. |
| `roles/common/files/bin/codex-bind-tmux-pane` | After the three `@codex_session_*` set-options, run the Part 1 label refresh. Before exiting, if `@agent_worktree_path` is unset on the pane, emit Part 2 JSON. |
| `tests/` | New tests (or extensions of `tmux-label-contract.sh`) for both Part 1 (same-pane refresh) and Part 2 (additionalContext emission on cross-pane resume). |

No changes to ansible tasks, tmux.conf, settings.json templates, or any other file.

### Boundaries

- `tmux-claude-session-start` and `codex-bind-tmux-pane` remain SessionStart hooks. They gain two responsibilities beyond "write session-id state": refresh visible label, and (conditionally) nudge the agent.
- `tmux-update-pane-label`, `tmux-window-label`, and `tmux-agent-worktree` are unchanged.
- `repo-start` and `tmux-agent-worktree set` remain the sole writers of `@agent_worktree_path`. The hook only requests the agent to invoke them.

## Error handling

- Both label helpers are invoked with `|| true` and stderr discarded; failures are swallowed.
- The Part 2 reminder uses `jq -n` (existing dependency, already required by both scripts); failure of `jq` exits the script normally with no output — no reminder is injected, but the agent still functions.
- If `TMUX_PANE` is unset the hook exits earlier; neither Part 1 nor Part 2 runs.
- If the pane has been killed between SessionStart fire and hook execution, the helpers' own `tmux display-message` calls return empty and they exit 0.
- If neither label helper is on `$PATH` (e.g. fresh machine pre-provision), the `|| true` keeps the SessionStart hook successful and the agent continues uninterrupted.

## Testing and verification plan

### Local manual — same-pane (Part 1)

1. In a tmux pane, run `repo-start <branch>`. Confirm window renamed to `(branch) repo`.
2. Exit the (non-existent) agent or just `tmux rename-window junk`.
3. Run `claude --continue` (or `cldr`). Confirm the window is renamed back to `(branch) repo` within a second of resume.
4. Repeat with Codex (`cdxr`).

### Local manual — cross-pane (Part 2)

1. In Window A, run `repo-start feature-x` and start `claude`. Do some work. Note the window name `(feature-x) repo`.
2. Detach (`tmux detach`). Open a new tmux client / window.
3. In Window B (a fresh pane in `~`, with no `@agent_worktree_path` set), run `cldr` (or `claude --resume <same-id>`). The window name on resume initially shows the cwd-based fallback.
4. Confirm the agent receives the additionalContext nudge in its first turn and responds by running `tmux-agent-worktree set <absolute-path-to-worktree>`.
5. Confirm Window B is renamed to `(feature-x) repo` once the agent runs the command.
6. Repeat with Codex.

### Automated

Add tests that:

1. **Part 1 — Claude.** Spawn a tmux server, open a pane with a known stale `window_name`. Set `TMUX_PANE` and pipe `{"session_id":"x","source":"resume"}` to `tmux-claude-session-start`. Assert `window_name` was renamed to the expected pane-label.
2. **Part 1 — Codex.** Same, with `codex-bind-tmux-pane` and a synthetic payload `{"session_id":"x","cwd":"/tmp","transcript_path":"/tmp/t","source":"resume"}`.
3. **Part 1 — agent-worktree cache preserved.** Pre-set `@agent_worktree_path` and `@pane-label = "(foo) bar"`. Run the hook. Assert the cached label is preserved and the window is renamed to it.
4. **Part 2 — Claude nudge fires.** Pre-clear `@agent_worktree_path`. Pipe a `source=resume` payload. Capture stdout. Assert it parses as JSON with `hookSpecificOutput.hookEventName == "SessionStart"` and an `additionalContext` containing `tmux-agent-worktree set`.
5. **Part 2 — Claude nudge suppressed.** Pre-set `@agent_worktree_path = /tmp/foo`. Pipe a `source=resume` payload. Assert stdout is empty (no nudge).
6. **Part 2 — nudge text content.** Assert the emitted `additionalContext` mentions `tmux-agent-worktree set` and the phrase "active worktree", so the agent has unambiguous instructions.
7. **Part 2 — Codex** equivalents of 4/5/6 (synthetic payload omits `source` to confirm the gate is purely pane-state based).

These extend the existing `tmux-label-contract.sh` style; if a tmux fixture harness already exists, reuse it.

## Rollout

Single commit on a worktree branch, PR, merge. No migration: the change is additive. Visible effects:

- Same-pane resumes whose window name had drifted are silently corrected.
- Cross-pane resumes now produce one additional turn in which the agent republishes worktree state — visible but small, and only when actually needed.

## Out of scope / related

- **tmux-resurrect restore window-name staleness on shell panes.** When the tmux server restarts, `tmux-update-all-pane-labels` refreshes `@pane-label` for every pane but never renames windows. The SessionStart-based refresh covers agent panes that re-launch a CLI on restore; pure-shell panes are unaffected. Separate concern.
- **Multi-worktree sessions.** If the agent switched worktrees mid-session (e.g. ran `repo-start` twice for different branches), only the most recently published worktree is reflected. The nudge text instructs the agent to pick the "active" worktree, which it can determine from its history. No persistent multi-worktree state is maintained.
- **`cldr` / `cdxr` cwd normalization.** `cdxr` already cds into `@agent_worktree_path` (or `pane_current_path`) before exec. `cldr` does not cd. We do not change either; the agent-republish flow makes pane cwd irrelevant for labelling.
