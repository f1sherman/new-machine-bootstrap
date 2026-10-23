# Maintainable pstack integration

Status: self-approved under z-quick-pr. Supersedes the temporary-install decisions in the earlier pstack design.

## Requirements

Brian wants pstack installed as normal maintained tooling. Remove trial status from deployed skill text, metadata, and provisioning labels. Keep feedback as a separate one-shot continuation. Prove an actual workflow, not only packaging.

## Diagnosis

The installed adapter preserved unavailable Cursor model defaults and provided no usable local role map. A `how` invocation therefore stopped before its required explainer. No dependency release fixes this: cursor/plugins has no tags or releases, and its current main commit remains the installed pin. The defect is our adapter.

## Approach

1. Recommended: retain exact upstream files outside discovery, configure all default roles as inherit-parent in the adapter, map required delegates to discovered native agents, and maintain the snapshot with Renovate git-refs digest updates plus a deterministic updater.
2. Track upstream main on every provision. Rejected: behavior would change without a reviewable diff and could differ across machines.
3. Adopt a community fork. Rejected: unnecessary extra behavior source.

Use the current parent model by default. Explicit user role choices can use discovered models. A multi-agent workflow can run on one model; never describe it as multi-model evidence. Only an explicit requirement for unavailable model diversity blocks that requirement. Preserve authorization boundaries, independent review, and existing PR handling. A user-invoked workflow can use its required delegates when local policy permits; native implementation remains the default for ordinary steps.

## Updates

Pin cursor/plugins main by full SHA in vars/tool_versions.yml. A dedicated Renovate regex manager captures currentDigest with currentValueTemplate main, datasource git-refs, and the official repository URL. A package rule runs only bin/update-pstack and includes only the pin and vendor tree. Add that exact command to the existing workflow allowlist. git-refs has no release timestamps, so explicitly disable minimum release age for this dependency rather than stall updates. Renovate proposes reviewed update PRs; merges and provisioning remain the existing rollout boundary.

The Python stdlib updater fetches the exact pinned commit, selects complete pstack skills/agents/docs plus README/license, rejects symlinks and non-regular entries, preserves bytes and executable modes, and generates deterministic provenance and checksums. Validate before replacement. --check must detect extra, missing, changed, or mode-changed files without modifying the tree. Tests execute it against real local Git fixtures including a changed pin, deletion, unsafe inputs, and check-mode failure.

## Verification

Run real updater fixture tests RED then GREEN, regenerate the live snapshot, and require --check success. Validate Renovate extraction and configuration with the actual Renovate implementation when available. Provision managed skills twice and inspect the installed entry. Run the original read-only how question through the deployed entry, adapter, and required explainer on an available model. Record the exact boundary tested and residual cross-harness gaps. Perform one fresh-context final branch review and update PR 673 without merging.

The adapter change repairs routing rather than optimizes prompt length. Compare baseline and repaired role resolution under identical questions and collect behavior and token counts. Retain all unrelated safeguards. If any prompt component is optimized or removed, run leave-one-component-out ablations; wording-only removal of trial labels is not a safeguard change.

## Follow-up

Keep continuation auto_hfoc68pvzti for 2026-10-24T18:08:00Z targeting this thread. Rename it as a feedback check, not an installation lifecycle. It asks about usefulness; removal requires Brian's later decision. No expiration or deletion rule belongs in a skill.
