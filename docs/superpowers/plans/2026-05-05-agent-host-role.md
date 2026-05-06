# Agent Host Role Plan

## Goal

Add a reusable role for coding agent machines that need the pull-request workflow, raw PR creation guards, and optional commit-only runtime homes.

## Scope

- Add an `agent_host` role with Claude and Codex hook registration.
- Install `_pull-request`, platform PR helpers, proof helpers, `_review`, and `_commit` for normal agent users.
- Support runtime homes that install only `_commit` while keeping the raw PR creation blocker active with a custom reason.
- Keep foreground PR monitoring out of this role.

## Verification

- Add static role tests before implementation.
- Run blocker helper tests.
- Run targeted provisioning-layout tests.
- Run Ansible syntax checks where practical.
