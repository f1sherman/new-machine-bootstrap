# Pi Core Capability Trials Design

Status: Self-approved

## Goal

Improve Pi session reliability and cache observability with NMB-owned core
settings and bounded review criteria.

## Non-goals

- Do not configure behavior owned by an installed Pi package.
- Do not enable extended cache retention globally.
- Do not add schedules, telemetry collectors, or raw transcript storage.

## Assumptions

- NMB owns the Pi CLI and generic Pi configuration.
- HNP owns personal package choices and package-specific behavior.
- Real-use quality and cost must be reviewed before trial scope expands.

## Recommended approach

Manage Pi's complete built-in tool list as `read`, `bash`, `edit`, `write`,
`grep`, `find`, and `ls`. Enable `showCacheMissNotices`. Document bounded
reviews for both settings and command-scoped `PI_CACHE_RETENTION=long` trials.
Keep package-specific model routing and watchdog guidance in HNP.

## Alternatives considered

### Keep all capability settings in NMB

This centralizes configuration but violates the established package ownership
boundary. Rejected.

### Put all trials in HNP

This keeps personal policy together but makes HNP own generic Pi defaults.
Rejected.

### Split by ownership boundary

NMB owns core tools and cache behavior. HNP owns `pi-subagents` behavior. This
matches existing provisioning responsibilities and is the selected approach.

## Components and boundaries

`roles/common/tasks/pi_main_worktree_guard_settings.yml` manages the complete
core tool list and cache notices while preserving unrelated settings. The
focused behavioral test verifies the recursive merge and idempotence.
`docs/pi-capability-trials.md` defines bounded core trials. HNP separately owns
the scout route and watchdog trial.

## Failure handling and rollback

- Restore the prior complete tool list if native discovery is repeatedly worse.
- Change cache notices to `false` if they are materially distracting.
- Exit a process started with `PI_CACHE_RETENTION=long` to end that trial.

## Verification

1. Run the focused settings provisioning test.
2. Run Ansible syntax and formatting checks.
3. Provision from the feature worktree.
4. Verify the deployed core values without printing unrelated settings.
5. Start a fresh Pi process and verify the native tools are exposed.

## Review policy

Review structured tools after 5–10 representative sessions. Compare at least
three similar sessions per cache-retention condition. Store bounded metrics only.
