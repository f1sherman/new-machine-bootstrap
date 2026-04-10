# Personal Commit Skill Runtime Split

**Status:** Approved
**Date:** 2026-04-09

## Goal

Fix `personal:commit` so Codex can use it successfully without breaking the existing Claude workflow.

## Background

`personal:commit` is currently installed from the shared skill directory at `roles/common/files/config/skills/common/committing-changes/SKILL.md`. That file tells the runtime to dispatch `personal:committer` as a foreground agent.

That instruction works only in the Claude deployment model, where `personal:committer` exists as a managed agent file under `roles/common/templates/dotfiles/claude/agents/personal:committer.md` and is deployed into `~/.claude/agents/`.

For Codex, the same shared `SKILL.md` is copied into `~/.codex/skills/`, but there is no corresponding Codex-discoverable `personal:committer` entity. The result is a broken skill: Codex is told to hand off work to something that does not exist in its runtime.

The root cause is packaging. Runtime-specific workflow instructions were placed in the shared `common` skill layer instead of being split by tool.

## Design

### Skill ownership

`committing-changes` becomes a layered skill:

- `roles/common/files/config/skills/common/committing-changes/commit.sh` remains shared. It is the implementation helper both runtimes can call.
- `roles/common/files/config/skills/claude/committing-changes/SKILL.md` becomes the Claude-specific workflow description.
- `roles/common/files/config/skills/codex/committing-changes/SKILL.md` becomes the Codex-specific workflow description.

The shared `common` directory no longer owns the `SKILL.md` for this feature. Shared directories are for shared assets; runtime behavior belongs in the runtime-specific trees.

### Installation order

`roles/common/tasks/main.yml` currently installs Claude-specific skills first and common skills second, and does the same for Codex. That means the shared layer wins whenever the same skill exists in both places.

Change the install order for both runtimes so `common` is copied first and the runtime-specific tree second:

1. Copy `roles/common/files/config/skills/common/` into the target skills directory.
2. Copy the runtime-specific tree (`claude/` or `codex/`) into the same target directory afterward.

This creates an intentional override model:

- Shared assets come from `common`.
- Runtime-specific `SKILL.md` files can replace shared ones cleanly.
- Future overlaps resolve predictably instead of accidentally.

### Runtime behavior

The Claude skill keeps the current behavior. It should continue to:

1. Write a 2-4 sentence session summary.
2. Dispatch `personal:committer` as a foreground agent.
3. Report the agent's returned `git log` output to the user.

The Codex skill keeps the same high-level user experience but uses Codex-native delegation instead of referring to `personal:committer`.

The Codex `SKILL.md` should instruct Codex to:

1. Write a 2-4 sentence summary of what changed, why, and any key decisions made.
2. Call `spawn_agent` with a worker prompt that embeds the commit workflow directly, then wait on that agent immediately so the handoff behaves like a foreground step.
3. Report the worker's result back to the user.

The worker prompt should tell the agent to:

1. Run `git status`, `git diff`, and `git diff --stat`.
2. Decide whether the session should produce one commit or multiple atomic commits.
3. Use `commit.sh` to stage, commit, and push each commit.
4. Retry `commit.sh` with `--force` if the only failure is that a file is gitignored.
5. Return `git log --oneline -n <count>` on success.
6. Stop and report the failure output if the tree is clean or push fails.

This keeps the git-inspection and commit-planning context out of the main Codex conversation while avoiding any dependency on a non-existent Codex skill or agent name.

### Scope

This change is intentionally narrow:

- Fix `personal:commit` packaging and Codex behavior.
- Preserve the existing Claude-side `personal:committer` flow.
- Keep `commit.sh` shared.

This change does not:

- Redesign other shared skills.
- Remove the Claude agent template.
- Change commit policy, commit message style, or the `commit.sh` contract.

## Verification

Verification should happen at the repo and provisioning level, not by hand-editing files in `~/.codex` or `~/.claude`.

1. Confirm the repo contains:
   - shared `commit.sh` under `roles/common/files/config/skills/common/committing-changes/`
   - Claude `SKILL.md` under `roles/common/files/config/skills/claude/committing-changes/`
   - Codex `SKILL.md` under `roles/common/files/config/skills/codex/committing-changes/`
2. Confirm `roles/common/tasks/main.yml` installs `common` before runtime-specific skills for both Claude and Codex.
3. Run `ansible-playbook playbook.yml --syntax-check` to verify the playbook remains valid after the task-order change.
4. Run `bin/provision` on a machine with this repo deployed.
5. Confirm the installed Codex skill no longer contains any reference to `personal:committer`.
6. Confirm the installed Claude skill still dispatches `personal:committer`.

## Files expected to change during implementation

1. `roles/common/tasks/main.yml`
2. `roles/common/files/config/skills/common/committing-changes/SKILL.md` (remove from the shared layer)
3. `roles/common/files/config/skills/claude/committing-changes/SKILL.md`
4. `roles/common/files/config/skills/codex/committing-changes/SKILL.md`
