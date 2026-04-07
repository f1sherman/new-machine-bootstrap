# Auto-trust mise configs under `~/projects`

**Status:** Approved
**Date:** 2026-04-07

## Goal

Eliminate manual `mise trust` prompts for any mise config file under `~/projects` on macOS and Linux dev hosts. Avoid the recurring chore of running `mise trust` after every `git worktree add` or fresh clone.

## Background

Mise refuses to load potentially-dangerous features (env vars, templates, `path:` plugin versions) from a config file until that file has been explicitly trusted. Today this project handles trust three ways:

1. `roles/common/tasks/main.yml:312` — Ansible task `Trust mise config (Linux)` runs `mise trust {{ playbook_dir }}/mise.toml` on Debian hosts. Trusts only the bootstrap repo's own `mise.toml`.
2. `roles/common/templates/dotfiles/zshrc:243-245` — `worktree-start` runs `mise trust "$path"` for each newly-created worktree.
3. `roles/macos/templates/dotfiles/bash_profile:288-290` — same as above for bash.

This works but is incomplete: any mise config under `~/projects` that wasn't created via `worktree-start` (e.g., a fresh `git clone` or a hand-created `.mise.toml`) still prompts. As a consequence, `~/.local/state/mise/trusted-configs/` already contains 115+ entries from manual trusting.

Mise has a setting purpose-built for this: `trusted_config_paths`. It is a list of directory prefixes; any config file under any listed prefix is automatically trusted. The setting is currently empty.

## Design

### Single change: add an Ansible task

Add an idempotent task pair to `roles/common/tasks/main.yml` that ensures `$HOME/projects` is present in mise's `trusted_config_paths` list:

```yaml
- name: Get current mise trusted_config_paths
  command: mise settings get trusted_config_paths
  register: mise_trusted_paths
  changed_when: false

- name: Auto-trust mise configs under ~/projects
  command: mise settings add trusted_config_paths "{{ ansible_facts['user_dir'] }}/projects"
  when: ('"' + ansible_facts['user_dir'] + '/projects"') not in mise_trusted_paths.stdout
```

The task runs unconditionally on every platform — no `os_family` or `CODESPACES` guard. On Codespaces `~/projects` does not exist, so adding it to the trust list is a harmless no-op (mise will simply never match anything against that prefix).

`mise settings add` writes to `~/.config/mise/config.toml`, which mise itself already manages (e.g., when `mise use --global node@...` runs in the existing playbook). Using mise's own subcommand avoids racing with mise's writes to that file.

#### Why the quoted substring check

`mise settings get trusted_config_paths` prints the list as a JSON-style array, e.g. `["/Users/brian/projects"]`. A naive substring check for `/Users/brian/projects` would false-positive on a sibling such as `/Users/brian/projects-old`. Wrapping the path in literal quotes (`"/Users/brian/projects"`) makes the match exact: the closing `"` only matches when the path ends precisely there.

`mise settings add` itself deduplicates — running it twice with the same value produces one entry — so the `when` guard exists for idempotent reporting (skipped vs. changed), not correctness.

#### Task ordering

The playbook installs platform packages (including `mise`) in `pre_tasks` before the `common` role runs (`playbook.yml:16-24`). The new tasks live in the `common` role, so `mise` is guaranteed to be on PATH when they execute. The existing `Trust mise config (Linux)` task in the same file already relies on this ordering.

### What stays in place

The following existing trust mechanisms are **kept unchanged** because they handle the Codespaces case, where the bootstrap repo lives at `~/new-machine-bootstrap` (not under `~/projects`) and worktrees live under `/workspaces/...`:

- `roles/common/tasks/main.yml:312` — `Trust mise config (Linux)` task
- `roles/common/templates/dotfiles/zshrc:243-245` — per-worktree `mise trust` call
- `roles/macos/templates/dotfiles/bash_profile:288-290` — per-worktree `mise trust` call

On macOS and Linux dev host these become cheap no-ops once the new task has run (mise short-circuits trust calls for already-trusted paths). On Codespaces they remain load-bearing.

## Verification (Red/Green)

1. **Red.** Pick a mise config under `~/projects` not currently in the trusted-configs cache (or run `mise trust --untrust` against an existing one), then run `mise current` from that directory. Expect mise to print an "untrusted config" warning and refuse to load env/template features.
2. **Green.** Run `bin/provision`. Confirm `mise settings get trusted_config_paths` includes `/Users/<user>/projects`. Re-run `mise current` from the same directory — the warning should be gone and the config should load cleanly.
3. **Idempotency.** Re-run `bin/provision`. The "Auto-trust mise configs under ~/projects" task must report `skipping` (not `changed`) because its `when` guard sees the path is already in the list. The "Get current mise trusted_config_paths" task is `changed_when: false` and should report `ok`.

## Out of scope

- Removing the existing per-worktree `mise trust` calls or the `Trust mise config (Linux)` task. These remain because Codespaces still needs them.
- Adding `/workspaces` to `trusted_config_paths` for Codespaces. The user explicitly chose to leave Codespaces alone in this iteration.
- Cleaning up the 115+ stale entries already in `~/.local/state/mise/trusted-configs/`. They are harmless and orthogonal to this change.
