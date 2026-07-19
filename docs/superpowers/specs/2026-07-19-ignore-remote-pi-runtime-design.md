---
date: 2026-07-19
topic: Ignore Remote Pi repository runtime state globally
status: approved
---

# Design: ignore Remote Pi repository runtime state globally

## Goal

Prevent Remote Pi's per-directory `.pi/remote-pi/config.json` from dirtying Git repositories and blocking repository cleanup.

## Design

Add `.pi/remote-pi/` to NMB's managed global Git ignore template at `roles/common/templates/dotfiles/gitignore`. The deployed `~/.gitconfig` already uses `~/.gitignore` through `core.excludesfile`, so one targeted entry applies to every repository on the machine.

Do not ignore all of `.pi/`; future project-owned Pi configuration must remain visible to Git. Keep existing Remote Pi files in place because they contain intentional per-directory runtime settings.

## Verification

A focused contract test will assert that the managed template contains `.pi/remote-pi/` and does not contain a blanket `.pi/` rule. After provisioning, `git check-ignore -v .pi/remote-pi/config.json` must resolve through the deployed global ignore file, and the primary checkout must remain clean.
