# Install the pstack control-cli dependency

Status: self-approved.

## Goal and evidence
A poteto-mode task stopped because the adapter requires unavailable essential skills to block. The managed snapshot selects deslop from cursor-team-kit but omits control-cli. Upstream control-cli is a skill for local terminal harnesses, not a binary.

## Approach
Select the complete control-cli directory from the existing pinned cursor/plugins commit. Require its SKILL.md before replacing the snapshot. Existing pstack-dependencies synchronization and recursive skill links deploy it to Pi, Claude Code, and Codex without new Ansible tasks. Preserve the upstream license and generated provenance.

Alternatives: weaken the adapter to allow substitution (reject: changes the requested workflow); install all cursor-team-kit skills (reject: unnecessary scope and dependencies).

## Boundaries
Do not change prompts, adapter safeguards, the version pin, or other skills. Do not resume or modify the reported thread. Assume the existing dependency installation pattern is sufficient. Remote deployment remains separate from local proof.

## Verification and rollout
Extend the production updater fixtures to verify complete control-cli support files and fail-closed handling of a missing required entry. Run updater tests, regenerate and check the pinned snapshot, provision managed-skills, and confirm all three harness links resolve. Exercise the installed skill through a local deterministic terminal harness. The original unrelated repair workflow will not be rerun; its live recovery remains unverified. Reload an existing agent session after provisioning to refresh its skill catalog.
