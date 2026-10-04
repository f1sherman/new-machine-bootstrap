# Permanent Pi external editor

Status: self-approved.

## Goal and scope

Provision Pi to use installed Neovim without special launch commands. Keep
unrelated Pi settings. Do not change shell variables, Vim configuration, or
system editor alternatives.

## Context and assumptions

The reported editor loaded a full vimrc in a build without scripting support.
The installed system vi is vim.tiny. Pi's externalEditor setting takes priority
over VISUAL and EDITOR. NMB installs Neovim before the common role runs on both
Linux and macOS. Its existing Pi settings task merges managed preferences.

## Approach

Resolve Neovim with command -v nvim on the target during provisioning. Store
that absolute executable path as externalEditor in the managed settings merge.
Fail provisioning if Neovim is unavailable. Run this read-only resolution in
check mode too. Preserve other settings through the existing merge.

Alternatives: setting externalEditor to nvim is smaller but still depends on
the launch PATH. Changing shell variables does not cover existing or non-shell
launch environments. Platform-specific paths couple settings to installers.

## Verification and rollout

Run the production settings task against an isolated agent directory. Verify
settings preservation, idempotence, and check mode. Use Pi's production settings
manager and external-editor function with EDITOR=vi, VISUAL=vi, and a restricted
PATH. Require a successful headless prompt round trip with normal Neovim config.
Do not add a permanent test for this declarative preference. macOS executable
resolution uses the same command but cannot be exercised on this Linux host.
Normal provisioning applies the setting. Existing sessions need /reload.
