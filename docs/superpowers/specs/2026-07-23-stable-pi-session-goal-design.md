# Stable Pi Session Goal Design

## Problem

Pi currently treats two different concepts as competing sources for session identity:

- a broad session goal describing the work theme;
- a git branch describing the current repository change.

The current goal subsystem reevaluates the broad goal after every expanded user prompt. This adds one mini-model call per interaction and asks a lightweight evaluator to distinguish conversational replies from genuine theme changes. Better prompting can reduce incorrect updates, but it does not fix the underlying mismatch: most prompts continue the same session theme, and branch names already describe individual implementation tasks.

A session should receive one stable goal near its beginning. That goal should remain the session's automatic visible identity across branch changes. When the broader theme genuinely changes, the user should request an explicit goal update.

## Goals

- Generate a concise session goal from the first expanded user prompt when no durable goal exists.
- Stop automatic goal evaluation after a valid goal has been persisted.
- Use the durable goal as the automatic Pi session name and tmux window/tab identity, even after feature branch creation.
- Keep branch and worktree identity available in pane context without allowing it to replace the goal.
- Provide a user-invoked Pi skill that updates the goal from supplied wording or infers it from the current conversation.
- Preserve manual Pi `/name` as an explicit visible-name escape hatch.
- Persist goal changes across resume, reload, fork, and tree navigation.
- Avoid permanent compatibility heuristics or prompt-classification rules.

## Non-goals

- Do not continuously infer whether the session theme changed.
- Do not model a hierarchy of goals, projects, branches, or subtasks.
- Do not rename git branches or change repository lifecycle behavior.
- Do not hide branch/worktree context from pane labels.
- Do not make the initial evaluator synchronous with the main agent.
- Do not change Claude or Codex subject behavior.

## User-visible Behavior

A new Pi session begins with:

```text
goal: determining…
```

The first expanded prompt starts one asynchronous goal evaluation. A successful result persists and displays a concise theme:

```text
goal: stable session identity
```

That goal becomes the automatically managed Pi session name and tmux window/tab label. Creating or switching to a feature branch does not replace it. Branch and worktree details remain visible in the pane context.

Later prompts do not start goal evaluators. The goal remains stable until explicitly updated.

The user can update it with supplied wording:

```text
/skill:z-update-session-goal authentication cleanup
```

Or ask the agent to infer a replacement from the conversation:

```text
/skill:z-update-session-goal
```

A manual Pi `/name` overrides the visible Pi/tmux identity without changing the durable goal shown in status. Automatic branch activity does not replace that manual name. A later goal update changes durable goal state but continues respecting the manual visible-name override.

## Architecture

### Session-goal owner

`roles/common/files/pi/extensions/managed-hooks.ts` remains the sole owner of Pi session-goal state. It restores custom `session-goal` entries, renders status, generates the initial goal, validates updates, and coordinates Pi/tmux identity.

The extension will expose one custom tool:

```text
set_session_goal(goal: string)
```

Both initial generation and explicit updates use one canonical application path so persistence, status rendering, managed naming, tmux publication, validation, and failure behavior cannot drift.

### Initial generation

`before_agent_start` schedules evaluation only when all of these are true:

- no valid durable goal is restored;
- no goal evaluation is already running;
- the current extension/session generation is still active.

The evaluator receives only the newest expanded user prompt and the existing concise noun-phrase instructions. It does not receive prior conversation context because initial generation occurs before a goal exists.

Once a valid goal is applied, all later prompts skip evaluation. The queue and prompt-coalescing subsystem is removed because there is no steady-state stream of evaluator requests.

If evaluation fails or returns invalid output, the status remains `goal: determining…`. A later prompt may retry while no valid goal exists. This bounds normal operation to one successful evaluator call while retaining recovery from transient failures.

### Durable state

Each accepted goal is appended as a `session-goal` custom entry. Restoration scans the active branch for the latest valid entry, preserving existing resume, fork, clone, reload, and tree-navigation semantics.

Explicit updates append only when the normalized goal differs from the current goal. Repeated equivalent updates return success without adding duplicate state.

### Tmux goal identity

Extend tmux task state with `goal` and `manual` sources in addition to `agent` and `branch`.

A goal uses active-state rendering:

- window/tab label: the goal;
- pane label: existing live worktree/branch context;
- status output: `active<TAB>goal<TAB><goal>`.

When branch activation detects an active goal or manual source, it still updates the bound worktree path and rerenders context, but it does not replace the task label or source with the branch. This isolates stable explicit identity from branch lifecycle changes.

Before initial goal generation succeeds, existing provisional agent-subject behavior remains available as a fallback. Applying the first goal replaces that provisional identity with the active goal source.

When `session_info_changed` identifies a name that does not match the extension-managed-name marker, it publishes an active manual source to tmux. This lets branch activation preserve the user's explicit visible override. An extension-managed session-name event publishes the active goal source instead and does not become manual merely because Pi emitted the same lifecycle event.

### Naming precedence

Visible naming follows this precedence:

1. manual Pi `/name`;
2. durable session goal;
3. provisional agent subject while the initial goal is unresolved;
4. existing directory fallback when no other identity exists.

A feature branch is contextual information, not a naming source, once a durable goal exists.

The existing managed-name marker continues distinguishing extension-owned Pi names from manual `/name` values. Goal status always updates, but the extension changes the Pi session name only when the current name is empty or still extension-managed.

`session_info_changed` distinguishes extension-managed names from manual names before publishing tmux state. Manual names therefore remain an explicit escape hatch without mutating durable goal state.

## Explicit Update Tool

Register `set_session_goal` with one required `goal` string.

The tool:

1. normalizes and validates the requested goal;
2. leaves state unchanged and returns an error for invalid input;
3. appends changed durable state;
4. updates `goal: <subject>` status;
5. updates the extension-managed Pi session name when no manual name is active;
6. publishes active goal identity to tmux when the pane is owned by this Pi process;
7. returns the applied durable goal.

Validation retains the current constraints:

- one line;
- repeated spaces collapsed;
- no control characters;
- no quotes or `goal:` prefix;
- non-empty;
- at most 80 characters.

Tool execution does not invoke another model. The calling agent chooses the phrase before calling it.

## Update Skill

Add the managed Pi skill:

```text
roles/common/files/config/skills/pi/z-update-session-goal/SKILL.md
```

The skill is user-invoked and supports Pi's standard appended arguments.

When arguments are supplied, the agent treats them as the requested theme, normalizes them into a concise noun phrase if needed, and calls `set_session_goal` exactly once.

When no arguments are supplied, the agent infers one broad noun phrase from the current conversation and calls `set_session_goal` exactly once.

The skill must not edit session files, invoke tmux helpers directly, call the initial evaluator, or update branch state. The registered tool is the only mutation interface.

## Failure Handling

Initial evaluator timeout, cancellation, nonzero exit, or malformed output preserves `goal: determining…` and permits a later retry. Diagnostics remain metadata-only and do not echo prompt or model output.

Tool validation failures return a clear error and leave durable, Pi, and tmux state unchanged.

If custom-entry persistence throws, no in-memory, status, Pi-name, or tmux identity update is published. Application must preserve all-or-nothing ordering as far as extension APIs permit.

Tmux publication failure does not roll back an already persisted Pi goal. It emits safe diagnostics; resume or a later label refresh can republish durable state.

A stale initial evaluator result cannot overwrite a goal set explicitly while it was running. Immediately before application, it must confirm that no durable/in-memory goal now exists and that session generation and file identity still match.

## Lifecycle

### Start, resume, and reload

Reset transient evaluator state, restore the latest valid goal, render status, and publish the restored goal as automatic identity unless a manual Pi name is active.

### First prompt

If no goal exists, launch one nonblocking initial evaluator. The main agent starts without waiting.

### Later prompts

If a goal exists, perform no goal-related model work.

### Tree navigation

Invalidate pending initial work, restore the selected branch's latest durable goal, and publish that goal according to normal manual-name precedence.

### Shutdown and session replacement

Abort pending initial evaluation and prevent late results from mutating replacement-session state.

### Branch activation

Update worktree/branch context but preserve active goal or manual identity.

## Testing

Extend `tests/pi-managed-hooks.sh` and tmux state/label contracts to cover:

- one initial evaluator call for the first prompt;
- no evaluator calls after a valid goal exists;
- retry after initial evaluator failure while the goal remains unset;
- restored durable goals suppressing evaluation immediately;
- explicit tool updates with supplied and inferred phrases arriving through the same tool interface;
- duplicate updates avoiding duplicate custom entries;
- malformed tool input leaving all state unchanged;
- explicit update winning a race with pending initial generation;
- manual `/name` preserving visible identity while durable goal status updates;
- active goal replacing provisional identity;
- branch activation preserving goal task source and label while refreshing worktree context;
- valid `active<TAB>goal<TAB><goal>` and `active<TAB>manual<TAB><name>` status parsing;
- extension-managed name events remaining goal-sourced while user `/name` events become manual-sourced;
- resume, tree navigation, shutdown, and stale-result safety;
- operation outside tmux;
- skill installation and exact tool-use instructions;
- absence of per-prompt queueing, coalescing, and preceding-assistant context logic.

Run focused Pi managed-hook, tmux agent-state, tmux label, skill-installation, and CI inventory tests. Provision with `bin/provision`, then confirm the deployed extension and skill match repository sources.

## Cost and Performance

Normal sessions use one mini-model call after the first prompt. Later prompts use no goal-evaluator calls. Explicit skill updates reuse the main agent's existing turn and make one local tool call, with no child model invocation.

The initial child remains asynchronous and isolated with thinking, tools, extensions, skills, templates, themes, context files, persistence, and approval disabled.

## PR Scope

PR #367 will replace its conversation-context implementation and documentation with this design. The obsolete per-prompt evaluator context, queueing, and associated tests will be removed. The PR title and body will be updated after implementation to describe stable initial goals and explicit skill-driven updates.
