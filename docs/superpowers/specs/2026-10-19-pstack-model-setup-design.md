# Machine-local pstack model setup

Status: self-approved under z-quick-pr.

## Goal and observed failure

Brian expected setup-pstack to discover available models, recommend models per role, and save the confirmed mapping. The adapter instead forced all delegates to inherit the parent. Restore setup and dispatch while preserving native harness and authorization rules. Brian also requires different choices on different machines, with no model IDs hard-coded in installed skills or repository configuration.

## Design

Add an explicit setup-pstack entry and shared MODEL-SETUP.md. Both the entry and pstack router use these local instructions instead of upstream Cursor configuration. Keep the upstream snapshot unchanged. The setup discovers the current harness's actual delegation model catalog, reads existing local choices, asks the upstream budget question, proposes every current upstream role, explains tradeoffs, and saves only after confirmation. Catalog membership is not proof of entitlement or optimality; inaccessible models must be reported rather than silently substituted.

Persist profiles at ~/.local/state/pstack/models/pi.json and claude-code.json. These are user-owned runtime state, explicitly not provisioned source/configuration. Each records the local hostname, harness, schema version, budget, and role selections. Never synchronize profiles across hosts. Provision only skills and the shared Ruby helper. A copied hostname-mismatched profile must require setup again.

The helper supports roles, show, save, and resolve. It validates schema and exact current catalog membership, uses private directories/files and atomic replacement under a lock, and never launches a process or changes credentials. Model values are exact native IDs; aliases inherit-parent/auto omit the model override. Optional thinking is permitted only for Pi and only when present in discovered supported levels. Claude delegate effort is not separately configurable unless a future actual tool schema supports it; budget informs model selection, not a fabricated effort field.

Every pstack invocation loads local policy before delegation. Precedence: explicit user choice, valid saved role mapping, unconfigured inheritance. A stale saved choice blocks that role and requests setup; it never silently falls back. Panel list length retains upstream meaning. Configured model identity must be honored even if a native agent profile has its own override. The parent chat model does not change. Native Pi and Claude are the supported setup targets; other harnesses retain honest inheritance until a supported setup path exists.

## Alternatives

Recommended: machine- and harness-local runtime profiles with a small validated helper and shared guidance. Repository-wide model lists violate Brian's host-specific requirement. Cursor .mdc rules cannot configure Pi or Claude. BB plugin migration is out of scope because Brian chose to retain the current integration. Pure prose-written state lacks the schema, atomicity, and stale-model boundary needed for reliable reuse.

## Verification

Use behavioral helper tests for durable state, host/harness separation, stale availability, unsupported thinking, panel counts, invalid writes, and symlink rejection. Do not add static skill-content tests. Compare matched old/candidate guidance and leave-one-component-out ablations for setup and saved-role dispatch, recording behavior and tokens; keep safety clauses that are not ablated. Use the real prior conversation as setup provenance and label constructed saved-profile decisions as synthetic. Separately run real CLI setup entry/help and a saved-model read-only delegate through Pi locally/remotely and Claude on dev. Keep proposed profiles unconfirmed in live user state; use disposable HOME/state for save/resolve proof. Provision the managed skill tree twice without touching profiles. Finish with fresh branch review and a PR.
