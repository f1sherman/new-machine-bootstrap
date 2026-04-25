# HNP And NMB Codex Shortcuts

**Date:** 2026-04-25
**Status:** Approved
**Repos affected:** `home-network-provisioning`, `new-machine-bootstrap`

## Background

Brian wants `hnp` and `nmb` to mean the two infrastructure repositories:

- `hnp` means `home-network-provisioning`
- `nmb` means `new-machine-bootstrap`

The executable shortcuts are owned by `home-network-provisioning`'s `personal-dev` role. This repository only needs the documentation update so agents understand the shorthand when Brian uses it.

## Goals

1. Document the `hnp` shorthand in this repo's `CLAUDE.md`.
2. Document the `nmb` shorthand in this repo's `CLAUDE.md`.
3. Keep script installation ownership in `home-network-provisioning`.

## Non-goals

- Adding an `nmb` script from this repository.
- Changing shell aliases or Codex configuration.
- Changing provisioning behavior in `new-machine-bootstrap`.

## Design

Add a short note near the top-level repository overview or agent behavior section of `CLAUDE.md`:

- `hnp` refers to `home-network-provisioning`
- `nmb` refers to `new-machine-bootstrap`

`AGENTS.md` is a symlink to `CLAUDE.md`, so editing `CLAUDE.md` is sufficient.

## Verification

Verify `CLAUDE.md` contains both shorthand mappings. The functional script tests live in `home-network-provisioning`, where the scripts are managed and installed.

## Risks

The documentation-only change has low risk. The main risk is drift if future agents assume `nmb` is owned here; the spec explicitly records HNP `personal-dev` as the owner for both executable shortcuts.
