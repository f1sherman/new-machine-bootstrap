---
date: 2026-04-10T11:12:02-05:00
git_commit: ed8f5d664bae0776806281c6ed3a214e6c99500b
branch: main
repository: new-machine-bootstrap
topic: "How the superpowers worktree behavior works for Claude and Codex"
tags: [research, codebase, superpowers, worktrees, claude, codex]
status: complete
last_updated: 2026-04-10
---

# Research: How the superpowers worktree behavior works for Claude and Codex

**Date**: 2026-04-10 11:12:02 CDT
**Git Commit**: ed8f5d664bae0776806281c6ed3a214e6c99500b
**Branch**: main
**Repository**: new-machine-bootstrap

## Research Question

How does the superpowers plugin implement the worktree behavior for both Claude and Codex?

## Summary

The worktree behavior is primarily a skill-driven workflow, not a special Claude-only or Codex-only runtime feature. Superpowers installs a shared skill library and a top-level `using-superpowers` skill that forces the agent to check for relevant skills before acting. In that workflow, `using-git-worktrees` is the skill responsible for isolated workspace setup.

For Codex, the Superpowers install works by exposing the skill directory through Codex's native skill discovery path at `~/.agents/skills/superpowers`, which points to `~/.codex/superpowers/skills/`. For Claude, the same skill library is installed through the Claude plugin marketplace. The current `using-git-worktrees` skill describes a manual git workflow: choose a worktree directory, verify ignore rules for project-local worktrees, run `git worktree add`, `cd` into the new path, install dependencies, and verify a clean baseline.

In this local environment, there is also a concrete shell helper, `worktree-start`, managed by the bootstrap repo. That helper performs the actual local setup work when invoked: it creates the linked worktree, copies `.coding-agent` files into the new worktree, copies `.claude/settings.local.json` when needed, trusts the new directory for Claude, runs `mise trust`, and then changes into the new directory. That helper lives in the shell dotfiles managed by this repository, not inside the Superpowers repo itself.

The Codex-specific reference docs also describe an additional environment-detection pattern for already-managed linked worktrees and detached HEAD sessions. That logic is documented in `codex-tools.md` and a Superpowers design spec, but it is not present in the currently installed `using-git-worktrees` skill file on this machine.

## Detailed Findings

### Superpowers uses skills to enforce the workflow

The top-level `using-superpowers` skill says skills must be invoked before any response or action when relevant, and that platform-specific mappings should come from the Codex reference docs. That is the mechanism that causes worktree setup behavior to happen as part of the broader Superpowers workflow rather than as a standalone command handler.

Relevant references:
- `/Users/brian/.codex/superpowers/skills/using-superpowers/SKILL.md:10-16`
- `/Users/brian/.codex/superpowers/skills/using-superpowers/SKILL.md:28-40`
- `/Users/brian/.codex/superpowers/skills/using-superpowers/SKILL.md:44-46`

### The shared Superpowers workflow activates `using-git-worktrees`

The Superpowers README describes the core workflow and explicitly lists `using-git-worktrees` as the second stage after brainstorming. It says this stage creates an isolated workspace on a new branch, runs project setup, and verifies a clean test baseline.

Relevant references:
- `/Users/brian/.codex/superpowers/README.md:108-124`

### Codex loads Superpowers through native skill discovery

The Codex-specific docs say Codex scans `~/.agents/skills/` at startup and that Superpowers is exposed by a symlink from `~/.agents/skills/superpowers/` to `~/.codex/superpowers/skills/`. That means the same `using-git-worktrees` skill content is visible to Codex without a separate implementation.

Relevant references:
- `/Users/brian/.codex/superpowers/docs/README.codex.md:22-39`
- `/Users/brian/.codex/superpowers/docs/README.codex.md:50-66`

### The current `using-git-worktrees` skill is a manual git worktree recipe

The installed skill file does not contain host-specific shell integration. It tells the agent to:

- select a directory using the priority order `.worktrees`, then `worktrees`, then `CLAUDE.md`, then ask the user
- verify project-local worktree directories are ignored
- compute the project name
- create a linked worktree with `git worktree add`
- change into the new worktree
- run project setup based on detected tooling
- run the test suite to verify a clean baseline

Relevant references:
- `/Users/brian/.codex/superpowers/skills/using-git-worktrees/SKILL.md:16-49`
- `/Users/brian/.codex/superpowers/skills/using-git-worktrees/SKILL.md:51-73`
- `/Users/brian/.codex/superpowers/skills/using-git-worktrees/SKILL.md:75-142`
- `/Users/brian/.codex/superpowers/skills/using-git-worktrees/SKILL.md:178-218`

### This repo adds a real shell helper that performs the local worktree setup

The bootstrap-managed shell config defines `worktree-start`. It:

- parses branch, path, start-point, and `--print-path` arguments
- finds the current repo root
- chooses a default path when no path is supplied
- validates branch existence, target path absence, and start point validity
- runs `git worktree add -b "$branch" "$path" "$start_point"`
- copies `.coding-agent` files into the new worktree
- copies `.claude/settings.local.json` into the new worktree when needed
- calls `claude-trust-directory` if available
- runs `mise trust` for the new path
- `cd`s into the new worktree unless `--print-path` was requested

Relevant references:
- `/Users/brian/projects/new-machine-bootstrap/roles/common/templates/dotfiles/zshrc:94-123`
- `/Users/brian/projects/new-machine-bootstrap/roles/common/templates/dotfiles/zshrc:125-250`
- `/Users/brian/projects/new-machine-bootstrap/roles/macos/templates/dotfiles/bash_profile:262-294`

### Codex-specific environment detection is documented separately

The Codex tool mapping file documents a pattern for detecting when the agent is already inside a linked worktree by comparing `git rev-parse --git-dir` and `git rev-parse --git-common-dir`, and for detecting detached HEAD by checking `git branch --show-current`. A design spec in the Superpowers repo describes using those signals to skip manual worktree creation in Codex App-managed worktrees and to adjust finishing behavior accordingly.

However, the installed `using-git-worktrees` skill file on this machine does not currently include that Step 0 detection section. The detection behavior is therefore documented in references and design material, but not visible in the current active skill body.

Relevant references:
- `/Users/brian/.codex/superpowers/skills/using-superpowers/references/codex-tools.md:73-100`
- `/Users/brian/.codex/superpowers/docs/superpowers/specs/2026-03-23-codex-app-compatibility-design.md:7-60`
- `/Users/brian/.codex/superpowers/docs/superpowers/specs/2026-03-23-codex-app-compatibility-design.md:64-87`

## Code References

- `/Users/brian/.codex/superpowers/skills/using-superpowers/SKILL.md:10` - Enforces mandatory skill usage.
- `/Users/brian/.codex/superpowers/skills/using-superpowers/SKILL.md:28` - Describes how different platforms load skills.
- `/Users/brian/.codex/superpowers/README.md:108` - Lists `using-git-worktrees` in the core workflow.
- `/Users/brian/.codex/superpowers/docs/README.codex.md:52` - Explains Codex native skill discovery and symlink layout.
- `/Users/brian/.codex/superpowers/skills/using-git-worktrees/SKILL.md:16` - Directory selection rules for worktree creation.
- `/Users/brian/.codex/superpowers/skills/using-git-worktrees/SKILL.md:55` - Ignore verification requirement for project-local worktrees.
- `/Users/brian/.codex/superpowers/skills/using-git-worktrees/SKILL.md:83` - Worktree creation step using `git worktree add`.
- `/Users/brian/projects/new-machine-bootstrap/roles/common/templates/dotfiles/zshrc:125` - `worktree-start` function entry point.
- `/Users/brian/projects/new-machine-bootstrap/roles/common/templates/dotfiles/zshrc:217` - Actual `git worktree add -b ...` execution in the helper.
- `/Users/brian/projects/new-machine-bootstrap/roles/common/templates/dotfiles/zshrc:222` - `.coding-agent` sync into the new worktree.
- `/Users/brian/projects/new-machine-bootstrap/roles/common/templates/dotfiles/zshrc:224` - `.claude/settings.local.json` copy logic.
- `/Users/brian/projects/new-machine-bootstrap/roles/common/templates/dotfiles/zshrc:233` - Claude directory trust hook.
- `/Users/brian/projects/new-machine-bootstrap/roles/common/templates/dotfiles/zshrc:243` - `mise trust` call for the new worktree.
- `/Users/brian/projects/new-machine-bootstrap/roles/common/templates/dotfiles/zshrc:247` - Final `cd` into the new worktree.
- `/Users/brian/.codex/superpowers/skills/using-superpowers/references/codex-tools.md:73` - Codex worktree environment detection guidance.
- `/Users/brian/.codex/superpowers/docs/superpowers/specs/2026-03-23-codex-app-compatibility-design.md:32` - Read-only git detection design for linked worktrees and detached HEAD.

## Architecture Documentation

The current architecture has three layers:

1. Superpowers installation and discovery.
   Claude gets the skills through plugin installation. Codex gets them through its skill discovery path and the `~/.agents/skills/superpowers` symlink.

2. Skill-driven behavior.
   The `using-superpowers` skill forces the agent to use relevant skills, and the `using-git-worktrees` skill defines the worktree workflow as instructions.

3. Local environment helpers.
   This bootstrap repo provides `worktree-start` and related shell helpers that perform the filesystem and trust setup around `git worktree add`.

The important boundary is that Superpowers itself defines the workflow, while this machine's dotfiles provide the concrete convenience function that can implement part of that workflow.

## Related Research

- None in this repository for the Superpowers worktree flow specifically.

## Open Questions

- Whether the currently installed Claude plugin package contains any additional worktree-specific behavior outside the shared skill files was not investigated here.
- The Codex reference docs describe linked-worktree detection for already-managed workspaces, but the installed `using-git-worktrees` skill on this machine does not currently show that logic inline.
