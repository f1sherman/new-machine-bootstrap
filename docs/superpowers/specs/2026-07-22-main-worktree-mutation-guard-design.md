# Main Worktree Mutation Guard Design

## Problem

Pi currently blocks built-in `edit` and `write` calls targeting `main`, but known writers invoked through `bash` can bypass that gate. A feature-worktree subagent used an absolute primary-worktree path with `edit`, then repeated the mutation through a Python heredoc, leaving duplicate uncommitted changes on `main`.

## Goals

- Keep normal shell access; do not introduce a read-only allowlist.
- Block known mutation forms only when they target a primary worktree currently on `main`.
- Protect absolute primary paths referenced from feature worktrees.
- Explicitly load the guard in managed Pi subagent children.
- Regress the exact absolute `edit` and Python `Path.write_text` incident paths.

## Non-goals

- A complete shell parser or OS sandbox.
- Blocking unknown commands.
- Defending against deliberate obfuscation or dynamically constructed writers.

## Architecture

Create `roles/common/files/pi/extensions/main-worktree-guard.ts` as a focused tool-call gate. It discovers the target Git root, current branch, and whether the target is a primary or linked worktree. `edit` and `write` remain blocked only for primary `main` targets. Session, tmux, and subject behavior stays in `managed-hooks.ts`.

For `bash`, track shell segments, explicit `cd`, and `git -C` context. Deny known mutation categories when their effective target is protected:

- output redirection and `tee`;
- `rm`, `mv`, `cp`, `install`, `touch`, `mkdir`, `rmdir`, `ln`, `truncate`, `patch`, `chmod`, and `chown`;
- in-place `sed` and `perl`;
- direct Git working-tree mutation such as `restore`, `clean`, `reset`, `checkout`, `switch`, and `apply`;
- obvious inline interpreter write APIs, including Python `Path.write_text`, `Path.write_bytes`, and writable `open()` modes, plus equivalent Ruby and Node calls.

Unknown command forms remain allowed. Block messages name the mutation category and protected worktree.

Provision the extension globally. Merge Pi settings so managed builtin subagents explicitly receive the deployed guard through `subagentOnlyExtensions`; preserve existing packages, model, theme, and user settings.

## Testing

Add deterministic contracts for absolute and relative tool targets, each deny category, feature-worktree allowances, read-only commands, and the exact Python heredoc escape. Add provisioning coverage for extension installation and settings merging. Run focused Pi contracts, CI inventory, Ansible syntax, full provisioning, then a real child probe.

## Residual risk

This is intentionally a denylist, not a sandbox. Novel writers or indirect/dynamic commands can evade static inspection. Future incidents should add narrow regression rules.
