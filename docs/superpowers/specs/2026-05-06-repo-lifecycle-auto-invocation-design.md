# Repo Lifecycle Auto-Invocation Design

## Problem

`repo-start` and `repo-end` are deployed and documented in `CLAUDE.md`, but no
automated mechanism funnels work through them. Existing hooks only catch:

- Direct `git worktree add/remove` (redirects to `repo-start`/`repo-end`)
- `Edit`/`Write` while on `main` (redirects to `repo-start`)

These leave gaps:

- `git checkout -b`, `git switch -c`, `git branch <new>` create a branch
  without firing any hook.
- `kickoff` is still installed and is the agent's habitual entry point; it
  does not delegate to `repo-start`.
- `_clean-up` calls `git-clean-up` (post-PR-merge sweep) and never touches
  `repo-end`, so the lifecycle "close" path never runs through it.
- Initiating skills (`superpowers:brainstorming`, `_spec-first`,
  `_spec-to-pr`) provide no nudge toward `repo-start` even when the agent is
  on `main`.

Net effect: the helpers exist but get bypassed in practice. Shell history
shows zero invocations of either script since they were installed.

## Goals

- Provide a gentle, non-blocking nudge when the agent invokes an initiating
  skill (`brainstorming`, `_spec-first`, `_spec-to-pr`) while on `main`,
  pointing at `repo-start`.
- Provide a hard fence that blocks agent-initiated branch creation by any
  path other than `repo-start`.
- Make `_clean-up` exercise `repo-end` so the close-side helper is reachable
  through the standard cleanup skill.

## Non-Goals

- Modifying `kickoff` or `cleanup-branches`. Both stay as-is.
- Modifying upstream `superpowers:*` skills. Behavior change for those
  comes only via hooks, not skill edits.
- Persisting per-worktree "started" state (no git-config marker, no state
  files). Branch identity is the only signal we need.
- Auto-invoking `repo-end` from any skill other than `_clean-up`. No hook
  on `superpowers:finishing-a-development-branch`.

## Design

Three components, each independently testable.

### Component A: initiation reminders

A new Claude hook `block-initiation-skill-on-main.sh` (name kept for symmetry
with the existing `block-*` family even though it does not block) fires on
`PostToolUse` for the `Skill` tool.

Behavior:

- Read `tool_input.skill` from stdin.
- Match against the set `{superpowers:brainstorming, _spec-first,
  _spec-to-pr}`.
- Resolve the current branch in the cwd via
  `git -C "$PWD" branch --show-current`.
- If the branch is literally `main`, emit a non-blocking
  `additionalContext` reminder pointing to `repo-start <branch>`. (Match
  the existing `block-main-branch-edits.sh` convention of hardcoding
  `main` rather than resolving the default branch generically.)
- Otherwise, emit nothing.

The hook never denies. The `PostToolUse` placement means the reminder lands
in the agent's context immediately after the skill content is loaded, so the
agent sees both the skill instructions and the reminder before taking
action.

The hook only inspects branch state; it never inspects the prompt, message
content, or anything outside the hook input JSON.

Codex cannot mirror the Claude `Skill` event directly. Instead, a
`UserPromptSubmit` hook (`codex-remind-repo-start-on-dev-prompt`) inspects
the submitted prompt, self-filters for development verbs such as add/fix/
implement/address, and emits the same non-blocking reminder when the repo is
on `main`. The reminder deliberately says `repo-start` chooses the feature
context "branch or worktree" because `repo-start` may use branch mode in the
main checkout depending on repo config.

### Component B: Branch creation hook

Extend `block-worktree-commands.sh` (or add a sibling hook
`block-branch-create.sh` if extending bloats the matcher) so that
`PreToolUse` on `Bash` denies and redirects when the command creates a new
branch:

- `git checkout -b <name>`
- `git switch -c <name>` (also `--create`)
- `git branch <name>` (when invoked with a positional arg that is not an
  existing branch — initial implementation can deny on any positional form
  to keep the regex simple, since safe forms like `git branch --list` and
  `git branch --show-current` use flags only)

The deny reason mirrors the existing pattern:

> Do not create branches directly. Use `repo-start <branch>` instead.

The hook continues to allow `repo-start`, `repo-end`, `kickoff`, and
read-only `git branch` invocations.

Decision: extend the existing `block-worktree-commands.sh` rather than add
a new hook file. Same matcher (`Bash`), same redirect target, same shape of
JSON output. Splitting buys nothing.

### Component C: `_clean-up` calls `repo-end`

Edit
`roles/common/files/config/skills/common/_clean-up/SKILL.md` so the skill
runs `repo-end` first (closes the local lifecycle: rebase, merge to main,
push, remove worktree+branch), then `git-clean-up` for the wider sweep
(remote branch deletion, multi-branch pruning, retained-branch reporting).

The two helpers serve different stages:

- `repo-end` integrates and tears down a *single* feature branch via local
  merge+push.
- `git-clean-up` is post-PR-merge cleanup: it assumes the merge already
  happened upstream and prunes the residue.

Naive sequencing of "`repo-end` then `git-clean-up`" misbehaves in the
post-PR-merge path: `repo-end` will try to rebase onto a main that already
contains the feature work (often as a squash commit), then attempt a
no-op merge and push. For squash-merged branches in particular, the rebase
will replay commits that look new relative to the squash commit, and
`repo-end` will create a duplicate merge.

To handle both flows, `repo-end` needs an idempotency check before the
rebase/merge phase: if the branch's content is already present in
`origin/<main>` — direct ancestor (`git merge-base --is-ancestor HEAD
origin/<main>`) or squash-merged equivalent — skip integration and proceed
straight to cleanup. Detection mechanism (patch-id comparison, `git cherry`,
or similar) is an implementation detail for the plan; the requirement here
is "do nothing harmful if the work is already upstream."

The skill change:

```diff
-git-clean-up
+repo-end || true   # no-op if already merged upstream; cleans worktree
+git-clean-up
```

The `|| true` is a placeholder; the actual idempotency lives inside
`repo-end`. The skill should fail loudly if `repo-end` returns a real error
(non-zero exit not attributable to "already merged"). Spec-level: prefer a
distinct exit code (e.g., 0 = success, 2 = "already merged, cleanup-only
done", any other = failure) so the skill can distinguish.

Additionally update the second invocation block (the monitor-driven path
with `--repo-dir` and `--branch`) the same way.

## Files Affected

- `roles/common/files/claude/hooks/block-initiation-skill-on-main.sh` (new)
- `roles/common/files/claude/hooks/block-initiation-skill-on-main.sh.test`
  (new)
- `roles/common/files/bin/codex-remind-repo-start-on-dev-prompt` (new)
- `roles/common/files/bin/codex-remind-repo-start-on-dev-prompt.test`
  (new)
- `roles/common/files/claude/hooks/block-worktree-commands.sh` (extended)
- `roles/common/files/claude/hooks/block-worktree-commands.sh.test`
  (extended)
- `roles/common/files/bin/codex-block-worktree-commands` (extended)
- `roles/common/files/bin/codex-block-worktree-commands.test`
  (extended)
- `roles/common/files/bin/repo-end` (idempotency check for already-merged
  branches)
- `roles/common/files/bin/repo-end.test` (new cases)
- `roles/common/files/config/skills/common/_clean-up/SKILL.md` (call
  `repo-end` before `git-clean-up`)
- `roles/common/tasks/main.yml` (register the new Claude PostToolUse hook in
  `~/.claude/settings.json` and Codex UserPromptSubmit hook in
  `~/.codex/hooks.json`)

The Codex Bash hook mirror (`codex-block-worktree-commands`) gets the same
branch-creation fence as the Claude Bash hook. The Codex reminder uses
`UserPromptSubmit` because current Codex hooks do not expose skill-loading as
a hookable tool event.

## Testing

Each new/extended hook gets its existing-style `.sh.test` neighbor with
`run_block_case`/`run_allow_case`/`run_empty_case` cases.

`block-initiation-skill-on-main.sh.test` covers:

- Reminder emitted when skill is `superpowers:brainstorming` and branch is
  `main`.
- Reminder emitted when skill is `_spec-first` and branch is `main`.
- Reminder emitted when skill is `_spec-to-pr` and branch is `main`.
- No output when skill is one of the targeted skills but branch is a
  feature branch.
- No output when skill is something else (e.g., `_commit`) regardless of
  branch.
- No output when the cwd is not in a git repo.
- No output for malformed/empty input JSON.
- Reminder text says `repo-start` chooses the feature context and does not
  promise a linked worktree.

`codex-remind-repo-start-on-dev-prompt.test` covers:

- Reminder emitted for development prompts while on `main`.
- No output for informational questions while on `main`.
- No output for development prompts on feature branches.
- No output outside git repositories or for malformed/empty input JSON.
- Reminder text points to `repo-start <branch>` and names "branch or worktree."

`block-worktree-commands.sh.test` (extended):

- Blocks `git checkout -b foo`.
- Blocks `git switch -c foo`.
- Blocks `git switch --create foo`.
- Blocks `git branch foo`.
- Blocks variants with `git -C ...`, `command git ...`, env-var prefixes,
  and chained shells (mirror the patterns the existing test suite covers
  for `worktree add`).
- Allows `git branch --show-current`, `git branch --list`,
  `git branch -d foo`, `git branch -D foo`, `git branch -v`.
- Allows `repo-start` and `kickoff`.

`codex-block-worktree-commands.test` gets the same branch-creation block/allow
coverage for the Codex-managed Bash hook.

`repo-end.test`:

- Existing happy-path test continues to pass.
- New: when `HEAD` is already an ancestor of `origin/<main>`, skip
  rebase/merge/push, run cleanup, exit cleanly (with whatever exit code
  the design lands on).
- New: when the branch was squash-merged upstream (commits not direct
  ancestors but tree is present), skip rebase/merge/push, run cleanup,
  exit cleanly.

End-to-end manual verification on the worktree this spec is written in:

1. With this branch checked out, invoke `superpowers:brainstorming`
   (already done — should not fire reminder since branch ≠ main).
2. From `main` in the main checkout, invoke `superpowers:brainstorming`
   and confirm the reminder appears.
3. Try `git checkout -b throwaway` from any cwd in the repo and confirm
   the deny.
4. Run `_clean-up` (or call `repo-end` directly) on a fully-merged feature
   branch and confirm no duplicate-merge or push occurs.

## Open Questions / Decisions Captured

- **`repo-end` idempotency (needs user signoff):** wiring `_clean-up` to
  `repo-end` requires a real behavior change to `repo-end` so it can be
  called safely in the post-PR-merge path (where the work is already in
  `origin/main`, often as a squash). Alternatives:
  1. Bake idempotency into `repo-end` (recommended; one canonical close
     helper covers both local-merge and post-PR-merge flows).
  2. Keep `repo-end` strict and have `_clean-up` call only `git-clean-up`
     (status quo for the post-merge path). The user's "have `_clean-up`
     call `repo-end`" intent goes unfulfilled in the PR-merge case but is
     satisfied for any non-PR direct-merge flow.
  3. Have `_clean-up` detect the merge state itself and conditionally
     call `repo-end` vs. `git-clean-up`. Splits responsibility across
     skill + helper rather than concentrating in the helper.

  Recommendation: option 1.

- **Hook split vs extend:** picked extend
  (`block-worktree-commands.sh` grows to cover branch creation). New
  filename would suggest a new responsibility; the existing file already
  represents "agent must funnel branch lifecycle through helpers."

- **Codex parity:** spec includes mirrored Codex Bash-guard updates and a
  Codex `UserPromptSubmit` reminder. The only non-mirrored piece is the
  Claude-specific `Skill` event, which Codex hooks do not expose.
