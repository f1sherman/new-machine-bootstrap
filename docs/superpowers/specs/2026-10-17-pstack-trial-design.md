# pstack trial

Status: self-approved under z-quick-pr.

## Goal and assumptions

Make poteto's pstack available in Brian's default managed setup for an explicit trial. Keep Superpowers and existing safety, repository, verification, and PR policies unchanged. Start a one-week feedback follow-up after local integration. This is an additive installation, not prompt optimization or a claim that pstack improves outcomes.

## Approaches

1. Recommended: vendor the official cursor/plugins pstack skills, agents, and harness documentation at commit 101b274dd991f694e1f7024be2157e5f3adf07de. Expose one user-only `pstack` entry point in Claude Code, Codex, and Pi. Keep upstream files outside skill discovery. Add a small adapter for tool names, paths, and unavailable capabilities.
2. Install the official Claude plugin. Good Claude support, but no official Pi or Codex integration; adds another plugin updater and duplicate discovery.
3. Install a community portable fork. Less adaptation, but adds a second source of behavioral changes and uncertain upstream synchronization.

## Boundaries

The existing canonical managed skill root owns one pstack skill directory with an upstream subdirectory. Only the wrapper is named SKILL.md in discovery; upstream markdown skill files use `.md` rather than `SKILL.md` to prevent recursive discovery. Preserve original content bytes and directory layout otherwise. The adapter resolves upstream `SKILL.md` references to these `.md` files. Copy complete skill support directories, agents, docs, README, and MIT license. Exclude assets and dormant automations. Record source commit, transforms, and SHA256 sums.

Explicit `pstack` invokes poteto-mode by default; `pstack how`, `pstack why`, and other exact skill directory names select a leaf. Sibling references resolve against the vendor tree. Parent instructions and tool contracts win over upstream defaults, including delegation authority, model selection, subagent reuse, publication, provisioning, and cleanup. Use current tools, never invented Cursor APIs. Do not install cursor-team-kit or write model rules. Unsupported mandatory capabilities stop that workflow with a clear gap; optional capabilities can be omitted explicitly.

No automatic activation or replacement of existing skills. Preserve existing invocation names. No upstream contributions, merges, credential changes, or new persistent native Pi schedules.

## Verification

Run the existing managed-skill linker behavior suite as baseline. Verify the pinned vendor tree against GitHub bytes and checksums. Provision the managed-skills tag through bin/provision twice and require the second run to report no changes. Confirm the deployed wrapper, support-file resolution, and absence of upstream leaf discovery across the three targets. Use a fresh-context branch review to challenge portability, policy boundaries, and unsupported workflow claims. Do not add static prose tests. Live skill quality and Claude/Codex execution remain trial evidence, not proven improvements.

## Follow-up and rollback

Register a one-shot BB automation targeting this thread for seven days after integration. Its scope is to ask Brian which workflows he used, what helped, what added overhead, and whether to retain, expand, or remove the trial. This thread owns completion, failure reporting, duplicate suppression, and safe retirement. No automatic code changes, merges, or deletions. Native continuations explicitly reject BB registration; BB thread scheduling is the supported continuation here.

Rollback removes the wrapper source from the managed pstack tree and reprovisions. The managed linker removes its own stale link; unrelated skills remain untouched.
