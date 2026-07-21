# Tmux Tab Indicators: Agent Activity + PR State

Date: 2026-07-20
Status: Approved

## Goal

Show two glyph indicators in the tmux window (tab) header for panes running a pi session:

1. **Agent activity**: 🤖 agent actively working, ⏳ waiting for user feedback.
2. **Aggregate PR state**: colored dot matching the pi status-bar PR states. With multiple PRs, show the "earliest" stage across all tracked PRs.

Example window name: `🤖🟢 my-branch`.

Scope: pi only (no Claude Code / Codex activity signal). Works both in local tmux and in remote tmux sessions (devpods/codespaces) via the existing structured remote-title channel.

## Non-goals

- Activity indicators for Claude Code or Codex sessions.
- Pane-border or status-right rendering; window tab name only.
- Exact truecolor matching in tmux (emoji dots approximate the status-bar palette).

## Aggregate PR state precedence

Earliest → latest; show the dot for the earliest-stage PR among non-terminal PRs:

1. ⚪ draft
2. 🔴 checks-failing
3. 🟡 changes-requested
4. 🔵 ready-for-review
5. 🟢 approved

If every tracked PR is terminal: 🟣 if any merged, else ⚫ closed. No tracked PRs → no dot. `unknown` states are ignored for aggregation unless all states are unknown, in which case no dot is shown.

## Architecture

Producer/renderer split across the two provisioning repos:

- **Producer (this repo, pi extensions)** writes tmux pane options describing state.
- **Renderer (new-machine-bootstrap)** owns glyph mapping and window-name rendering, inside the existing label pipeline (`tmux-window-label`, `tmux-remote-title`, `tmux-task-label`).

Pane options are the transport because they die with the pane (no stale persistent state) and work identically inside local and remote tmux servers.

### Pane option contract

- `@agent_activity`: `working` | `waiting` (absent = no pi session)
- `@pr_state`: one of `draft`, `checks-failing`, `changes-requested`, `ready-for-review`, `approved`, `merged`, `closed` (absent = no tracked PRs)

State names, not glyphs, cross the boundary; glyph choice is a renderer concern.

## Producer changes (bootstrap-brian-john)

Source: `roles/common/files/pi/extensions/`.

### pr-status extension

- New pure helper in `helpers.mjs`: `aggregateState(prs)` implementing the precedence above.
- After every render-worthy change (PR added, poll completes, `/pr-status-clear`), when `$TMUX_PANE` is set:
  - `tmux set-option -pt $TMUX_PANE @pr_state <state>` or `set-option -pu` to clear when no PRs / all unknown.
  - Best-effort nudge: run `tmux-window-label $TMUX_PANE` and `tmux-remote-title publish` (from `~/.local/bin`, ignore missing/failing) so the tab updates immediately rather than on the 60s status interval.
- All tmux interaction wrapped in try/catch; never surface errors to the session beyond a one-time warning.

### agent-activity extension (new)

`roles/common/files/pi/extensions/agent-activity.ts`, installed alongside the others by the existing provisioning task.

- `session_start` → set `@agent_activity waiting`
- `agent_start` → `working`
- `agent_end` → `waiting`
- `session_shutdown` → clear option (`set-option -pu`)
- Same no-op-without-`$TMUX_PANE` guard and best-effort nudge as above. Debounce is unnecessary: agent_start/agent_end fire per user turn, not per tool call.

## Renderer changes (new-machine-bootstrap)

### Glyph mapping

Single helper `roles/common/files/bin/tmux-indicator-glyphs`: takes `<activity> <pr_state>` (either may be empty) and prints the glyph prefix (e.g. `🤖🟢 `), empty output when both absent. Both `tmux-window-label` and the remote-marker parsing use it so mappings never diverge.

- Activity: `working` → 🤖, `waiting` → ⏳
- PR: `draft` ⚪, `checks-failing` 🔴, `changes-requested` 🟡, `ready-for-review` 🔵, `approved` 🟢, `merged` 🟣, `closed` ⚫
- Unrecognized values render nothing (forward compatibility).

### tmux-window-label (local panes)

After the final label is resolved and before `rename-window`: read `@agent_activity` and `@pr_state` from the active pane, prepend the glyph prefix. Applies uniformly across task states (provisional/active/completed/none). The 40-cell truncation in `tmux-task-label` already handles wide glyphs; prefix is added after truncation so the glyphs are never truncated away.

### Remote channel

Remote pi runs inside the remote tmux, so the producer options exist on the remote server. Propagation to the local tab:

- `tmux-remote-title`: read the two pane options; when either is set, append a suffix marker `[nmb-ind=<activity>,<pr_state>]` (ASCII state names, empty fields allowed, e.g. `[nmb-ind=working,]`) to the published title, following the `[nmb-edge=...]` convention. Marker order: `[nmb-ind=...]` before `[nmb-edge=...]` is not required; parsing strips each independently.
- Local parsing (`tmux-window-label`, `tmux-task-label`): strip the `[nmb-ind=...]` marker before structured-label parsing (alongside `strip_edge_marker`), capture its values, and prepend the corresponding glyphs to the extracted window label via `tmux-indicator-glyphs`.

## Error handling / staleness

- Every tmux invocation from the extensions is best-effort; failures degrade to "no indicator".
- Pane options are pane-scoped: closing the pane removes all state. Extension crash worst case: frozen indicator until the pane/session ends. Accepted.
- Renderer treats absent options as "render nothing" — panes without pi look exactly as today.

## Testing

- **bootstrap-brian-john**: `helpers.test.mjs` (node:test) covers `aggregateState` precedence, terminal-only handling, unknown handling. Extension-side tmux plumbing kept thin enough to not need integration tests.
- **new-machine-bootstrap**: extend the existing shell test suites (`tests/tmux-label-contract.sh`, agent-state tests) for: glyph prefixing local labels in each task state, `[nmb-ind=...]` emission in `tmux-remote-title` (via the env-injectable test hooks already present), and marker strip + glyph re-prefix on the extract side.

## Rollout

1. Land nmb renderer changes (safe no-ops until options/markers appear).
2. Land bootstrap producer changes.
3. `bin/provision` in both repos; verify locally, then in a devpod session.
