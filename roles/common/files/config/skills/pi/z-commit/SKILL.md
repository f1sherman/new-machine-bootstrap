---
name: z-commit
description: >
  Create git commits with no AI attribution.
  Use when creating git commits in the current repository.
---

# Commit Changes

Invoking this skill is explicit approval to commit the current repository state. This skill does not push.

Create the needed git commit or commits while keeping the main conversation focused on the higher-level task.
1. Write a 2-4 sentence summary of what you accomplished in this session - what changed, why, and any key decisions made. Include the exact list of files that should be committed.
2. Record the current commit with `git rev-parse HEAD`.
3. Spawn a `worker` subagent with your summary and file list. Set `agentContract: { version: 1 }` and omit `acceptance`. A commit-only worker changes Git history and normally leaves no worktree edits, so inferred mutation acceptance is not valid for this task. Instruct the subagent:

```text
You are responsible for creating the commit(s) for the current repository state.

Use this process:
1. Inspect the git changes with `git status --short`, `git diff --stat`, `git diff`, and `git diff --cached` when staged changes exist.
2. Decide whether to create one commit or multiple atomic commits. Keep each commit coherent and leave the repository in a working state after each commit.
3. Write imperative commit messages that explain why the change exists.
4. Never add AI attribution, "Generated with Codex", or "Co-Authored-By" lines.
5. For each commit, run `~/.pi/agent/skills/z-commit/commit.sh -m "<message>" file1 file2 ...`.
6. If `commit.sh` fails only because a file is gitignored, rerun the same command with `--force`, except never force-add an ignored file under `docs/superpowers/`; leave those local and omit them from the commit.
7. If there are no changes to commit, return `No changes to commit.` and stop.
8. On success, return a short success message (e.g., "Committed." or "Created 2 commits."). On failure, return the actual error output.
```

4. Wait for the subagent so the handoff behaves like a foreground step.
5. Validate the result yourself. Read the new `HEAD`, inspect the paths changed between the old and new commits, and run `git status --short -- <requested files>`.
   - Success requires `HEAD` to advance, every requested file to appear in the new commit range, and no requested file to remain changed or staged.
   - If `HEAD` did not advance and none of the requested files has a change to commit, report `No changes to commit.`
   - Otherwise, report failure with the failed check and the worker's actual error output. Do not treat clean requested paths as evidence that the worker made no change.
   - Ignore unrelated worktree changes when classifying the commit result. Leave those changes untouched.
6. Report the validated result to the user.
