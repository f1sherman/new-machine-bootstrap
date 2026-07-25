# Retire NMB HNP Launcher Ownership

**Date:** 2026-07-25
**Status:** Approved
**Canonical design:** `home-network-provisioning/docs/superpowers/specs/2026-07-25-hnp-launcher-ownership-design.md`

## Problem

NMB's broadly applied `common` role installs an HNP-specific `hnp` launcher. HNP's `personal-dev` role also renders the same command, so the last provision wins and behavior depends on repository order. The helper belongs only on HNP `personaldev` hosts and its canonical implementation belongs in HNP.

## Goals

1. Stop NMB from defining or installing executable `hnp` behavior.
2. Remove known stale NMB-managed launcher copies.
3. Never delete HNP-rendered, user-modified, or otherwise unknown launchers.
4. Remove NMB-only tests, workflow wiring, and implementation documents after their behavior moves to HNP.

## Design

NMB deletes its launcher source and common-role install task. It also deletes `tests/hnp.rb`, the corresponding integration-workflow step, and the earlier exclusive-attachment spec and plan whose implementation is moving to HNP.

NMB retains one migration-only cleanup task. The task computes the SHA-256 checksum of `~/.local/bin/hnp` and removes the file only when it matches a known historical NMB-managed launcher revision. It does nothing when the file is absent or its content is unknown. This prevents a later standalone NMB provision from deleting HNP's canonical rendered launcher.

The retired checksum set covers each distinct `roles/common/files/bin/hnp` revision from its introduction through PR #379. A focused behavior test runs the cleanup task with temporary homes and proves both sides of the boundary: content matching the configured retired checksum set is removed, while HNP-like content is preserved. The test overrides the checksum set with a small fixture hash rather than retaining a historical launcher implementation in NMB.

The cleanup task may be removed in a later change after all NMB-managed machines have converged through one successful provision.

## Deployment

HNP and NMB use separate coordinated pull requests. Prefer merging and provisioning HNP's ownership change first. Then merge this retirement change and run NMB provisioning on machines that previously received the common launcher. The checksum guard makes reverse ordering safe, but HNP provisioning is still required to establish desired state on `personaldev` hosts.

## Success Criteria

- NMB contains no executable `hnp` launcher implementation or install task.
- Known NMB-managed installed copies are removed during provisioning.
- HNP-rendered and unknown installed copies survive NMB provisioning.
- NMB's test inventory and integration workflow remain green after test retirement.
