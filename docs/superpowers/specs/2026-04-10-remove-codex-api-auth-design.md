# Remove Codex API Auth From The Repo

**Status:** Approved
**Date:** 2026-04-10

## Goal

Treat Codex subscription auth as the supported path in this repo without changing the repo's broader OpenAI key handling for other tools.

## Background

This repo previously managed Codex API-key auth by writing `~/.codex/auth.json` from either:

- `~/.config/api-keys/openai` on macOS
- `OPENAI_API_KEY` in Codespaces

That provisioning path was removed in commit `1eddcdd` (`Unset OpenAI API key for Codex shell wrapper`). The current repo state already reflects most of the desired direction:

- `roles/common/tasks/main.yml` still installs Codex CLI and manages workspace trust, but no longer writes `~/.codex/auth.json`.
- `roles/common/templates/dotfiles/zshenv` still exports `OPENAI_API_KEY` from `~/.config/api-keys/openai` as part of the repo's general API-key handling.
- `roles/common/templates/dotfiles/zshrc` wraps `codex` and unsets `OPENAI_API_KEY` so Codex can prefer subscription auth.
- `macos` still prompts for an OpenAI API key during bootstrap, and that behavior is intentionally unchanged for non-Codex consumers.

The requested change is intentionally narrow: remove any remaining Codex-specific API-auth intent from the repo while keeping the `codex()` wrapper as a safety guard.

## Design

### Supported Codex auth model

The repo will support Codex in this way:

- install the Codex CLI
- configure Codex trust settings for workspace directories
- allow Codex to authenticate via subscription

The repo will not:

- create or update `~/.codex/auth.json`
- describe Codex API-key auth as the intended path
- couple Codex runtime behavior to the OpenAI key file beyond the existing shell guard

### OpenAI key handling stays general-purpose

General OpenAI key handling remains unchanged:

- `macos` continues prompting for an OpenAI key
- `roles/common/templates/dotfiles/zshenv` continues exporting `OPENAI_API_KEY`
- any non-Codex tooling that depends on `OPENAI_API_KEY` keeps working as it does today

This preserves current behavior outside Codex and avoids turning a Codex cleanup into a broader OpenAI migration.

### `codex()` wrapper stays in place

The `codex()` function in `roles/common/templates/dotfiles/zshrc` remains part of the design.

Its role is defensive, not configurational:

- it prevents a globally exported `OPENAI_API_KEY` from overriding subscription auth
- it does not provision credentials
- it is the only intentional Codex-specific interaction with the OpenAI environment variable

If any wording near that wrapper still implies the repo is actively configuring Codex API auth, implementation should tighten the wording so it clearly describes a compatibility guard.

## Scope

This change is intentionally narrow:

- keep Codex CLI installation
- keep Codex trust configuration
- keep the `codex()` wrapper that unsets `OPENAI_API_KEY`
- remove or update any remaining repo text that implies Codex should use API-key auth from this repo

This change does not:

- remove OpenAI key prompts from `macos`
- stop exporting `OPENAI_API_KEY` globally
- change Anthropic configuration
- redesign how other tools obtain API keys

## Verification

Implementation should prove the repo state matches the design:

1. Search the repo for active references to `.codex/auth.json` and confirm no live task writes it.
2. Search the repo for Codex-specific API-auth wording and remove or update any misleading text.
3. Confirm the only remaining live Codex/OpenAI interaction is the `codex()` wrapper that clears `OPENAI_API_KEY`.
4. Run `ansible-playbook playbook.yml --syntax-check` to confirm repo validity after any changes.

## Files expected to change during implementation

1. `roles/common/templates/dotfiles/zshrc`

## Files expected to remain unchanged

1. `macos`
2. `roles/common/templates/dotfiles/zshenv`
3. `roles/common/tasks/main.yml`
4. Any other repo files unless verification reveals unexpected live Codex API-auth wording outside `zshrc`
