---
name: personal:commit
description: >
  Create git commits with no AI attribution.
  Use when the user asks to commit changes. Invoking this skill is explicit approval to commit, but not to push.
---

# Commit Changes

The user has approved committing, but not pushing. Delegate the git inspection and commit planning to a worker so the main conversation does not absorb the diff.

1. Write a 2-4 sentence summary of what you accomplished in this session - what changed, why, and any key decisions made.
2. Call `spawn_agent` with `agent_type: worker` and `fork_context: false` using the summary plus these instructions:

```text
You are responsible for creating the commit(s) for the current repository state.

Use this process:
1. Inspect the git changes with `git status --short`, `git diff --stat`, `git diff`, and `git diff --cached` when staged changes exist.
2. Decide whether to create one commit or multiple atomic commits. Keep each commit coherent and leave the repository in a working state after each commit.
3. Write imperative commit messages that explain why the change exists.
4. Never add AI attribution, "Generated with Codex", or "Co-Authored-By" lines.
5. For each commit, run `~/.codex/skills/committing-changes/commit.sh -m "<message>" file1 file2 ...`.
6. If `commit.sh` fails only because a file is gitignored, rerun the same command with `--force`.
7. If there are no changes to commit, return `No changes to commit.` and stop.
8. Do not push. Pushing requires separate user approval.
9. On success, run `git log --oneline -n <number-of-commits>` and return only that output.
```

3. Call `wait_agent` on the spawned agent immediately so the handoff behaves like a foreground step.
4. Report the worker result to the user.
