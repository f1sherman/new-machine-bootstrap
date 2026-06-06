# macOS Keychain Secrets Skill

**Status:** Approved
**Date:** 2026-06-06

## Goal

Add a shared skill that guides agents through safe setup and debugging of local
macOS Keychain secrets for app integrations, CLI tokens, and provider
credentials.

## Non-Goals

- Add helper scripts or wrappers around `security`.
- Change Ansible installation logic.
- Modify deployed files under `~/.codex`, `~/.claude`, `~/.agents`, or the
  user's live Keychain directly.
- Add automated tests for the skill content.

## Assumptions

- The skill should be available to both Claude and Codex.
- Existing common skill installation already copies shared skills into both
  runtime skill directories.
- The skill is operational guidance only; agents should still prefer
  application-specific wrappers when they exist.

## Recommended Approach

Create one docs-only shared skill at:

`roles/common/files/config/skills/common/macos-keychain-secrets/SKILL.md`

This matches the current packaging model. Common skills are copied into both
`~/.claude/skills` and `~/.codex/skills`, so no provisioning task changes are
needed.

## Alternatives Considered

Runtime-specific skill copies would allow Claude- or Codex-specific wording, but
there is no runtime-specific behavior in the current requirement. That would add
duplication without improving safety.

A helper script could hide `security` command details, but this request is about
teaching agents the right Keychain usage pattern. A script would expand scope
and require behavioral tests around secret handling and Keychain mutations.

## Skill Content

The skill will include these sections:

- **Diagnose:** Check keychain search list, default keychain, and login keychain
  file. It will state that the default keychain should be
  `~/Library/Keychains/login.keychain-db`, not `~/Library/Keychains`.
- **Prefer Existing App Wrappers:** Search the local codebase for Keychain
  wrappers and service/account naming before using direct `security` commands.
- **Direct Security Commands:** Use explicit login keychain path as the final
  argument for `security add-generic-password` and
  `security find-generic-password`.
- **Default Keychain Repair:** If the default keychain points at a directory or
  invalid path, ask before mutating it with `security default-keychain -s`.
- **Secret Handling:** Never print secrets, avoid shell history exposure, prefer
  existing authenticated tools or private files, and verify presence rather than
  value.
- **Failure Handling:** Distinguish missing items from Keychain failures. If
  macOS prompts repeat or the user cancels, stop.

## Installation

No Ansible task changes are required. The existing common skill copy tasks in
`roles/common/tasks/main.yml` install shared skills to both:

- `~/.claude/skills`
- `~/.codex/skills`

## Verification

Implementation verification should confirm:

1. `roles/common/files/config/skills/common/macos-keychain-secrets/SKILL.md`
   exists.
2. The skill includes the critical explicit keychain path rule.
3. The skill tells agents to ask before repairing the default keychain.
4. The skill tells agents not to print secrets.
5. `ansible-playbook playbook.yml --syntax-check` passes.

