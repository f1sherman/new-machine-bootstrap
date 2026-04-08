# Codex YOLO Alias

## Problem

The shared zsh configuration already includes a `claude-yolo` shortcut, but there is no matching shortcut for running Codex with its bypass flag. Adding the alias directly to the provisioned zsh template keeps the command available anywhere this repo manages shell configuration.

## Solution

Add a single alias to the shared zsh alias block in `roles/common/templates/dotfiles/zshrc`:

```zsh
alias codex-yolo='codex --dangerously-bypass-approvals-and-sandbox'
```

Place it next to the existing `claude-yolo` alias so related shortcuts stay grouped together.

## Scope

### In Scope

- Add `codex-yolo` to the shared zsh template
- Keep the alias expansion exactly equal to `codex --dangerously-bypass-approvals-and-sandbox`
- Verify the template change and a repo-appropriate provisioning check

### Out of Scope

- Changes to `roles/macos/templates/dotfiles/bash_profile`
- Converting the alias into a shell function or standalone script
- Renaming or restructuring the existing alias block
- Adding warnings, prompts, or guard rails around the command

## Behavior

After provisioning, interactive zsh shells managed by this repo expose `codex-yolo` as a shortcut for the full Codex bypass command. The alias does not change any other Codex defaults or shell behavior.

## Verification

1. Confirm the shared zsh template contains the new alias line in the alias block.
2. Run a repo-appropriate validation command after the change. For this repository, `ansible-playbook playbook.yml --syntax-check` is the minimum baseline check.
3. If practical in the current environment, inspect the rendered shell configuration after provisioning to confirm the alias is present in deployed zsh config.

## Risks

This change intentionally creates a short path to a high-privilege command. That is consistent with the requested behavior and the existing `claude-yolo` precedent, but it should remain a narrowly scoped alias addition rather than expanding into broader shell automation.
