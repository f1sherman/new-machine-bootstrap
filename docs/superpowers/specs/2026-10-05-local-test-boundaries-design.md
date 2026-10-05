# Local workflow test boundaries

Status: self-reviewed and self-approved.

## Goal and scope
Repair the local verification defects reported during PR #626 without modifying live systems or masking races. Treat the four affected fixtures as one bounded verification-boundary slice; Lua runtime availability is a separate prerequisite, not an application defect. No provisioning, package installation, push, PR creation, monitoring, or unrelated cleanup.

## Evidence and assumptions
The source baseline is d1438121. The historical plan records 47 passed / 15 failed: eleven missing Lua runtime lanes and four unrelated failures. Original failed PR logs disappeared during merged-worktree cleanup; historical baseline apt output is empty, while the other three historical baseline logs are green. Preserve fresh unmodified failures and diagnostics in `.superpowers/local-test-evidence/`.

Fresh apt tracing shows `/usr/bin/ansible-playbook` bypasses the intended bootstrap simulation. The real playbook reaches the fake sudo, which tries to exec `-H`. Accepting sudo flags alone is therefore unsafe and does not exercise bootstrap apt retry behavior. The other three fixtures pass fresh baseline runs; their historical intermittent failures are not proof of production defects.

## Approach and alternatives
Recommended: isolate the apt fixture's executable search path, permitting only its required host tools and fake apt/sudo/Ansible. Investigate timing fixtures at their observable state transitions; replace elapsed-time assumptions with explicit fixture readiness/release handshakes only where a reproduced failure establishes the cause. Keep existing deadlines and production safety behavior unchanged. If no cause can be established within bounded investigation, report the evidence gap rather than guessing.

Alternatives: teach fake sudo Ansible flags (reject: would permit a real playbook instead of testing bootstrap); widen deadlines or rerun until green (reject: masks races and violates the task); broad fixture/production rewrites (reject: excess scope without evidence).

## Components and boundaries
- Apt fixture: controlled PATH makes `ansible-playbook` absent until fake installation creates it; real apt and real provisioning must never execute. Existing behavioral assertions cover transient update/install locks, persistent locks, and non-lock failures.
- tmux fixture: test concurrent reservation occupancy, not simultaneous four-way startup-lock acquisition. Hold fake clients alive and unattached while each subsequent helper selects; observe four distinct reservations before explicit release, then verify child reaping and reservation cleanup. Preserve the separate slow-restore/startup-lock exclusion test. A zero-delay diagnostic reproduced three attachments because startup/cleanup contention exceeded the existing 1s fixture lock deadline; this is not reconstruction of the missing historical duplicate/count failure.
- repo-end fixture: callback timeout/descendant cleanup and captured EOF must remain bounded. Distinguish Git cleanup work before callbacks from callback lifecycle timing.
- Pi adapter fixture: authoritative registration/owned workspace cleanup and child termination remain bounded. Inspect fake CLI startup, cumulative registration deadlines, and interrupt/concurrent handshakes before selecting a fix.
- Lua: CI explicitly installs lua5.4. Use those existing eleven CI commands on a host with that prerequisite; do not add packages, skip tests silently, or change source to compensate.

## Verification and retained-test value
Run every affected fixture end to end, keep nonzero outputs, and inspect status and assertions. Retain tests only for material behaviors: package-manager lock handling prevents failed bootstrap; tmux reservation concurrency prevents incorrect terminal/session routing; callback proof/termination prevents unsafe cleanup/orphans; adapter fail-closed ownership prevents deleting or duplicating sessions. These execute production artifacts and protect complex behavior not covered by static validation. Do not add workflow bookkeeping or static-config tests.

Run relevant neighboring workflow tests and the workflow's available test commands without live provisioning/install steps. Report unavailable Lua lanes explicitly. Callback and adapter historical timing failures may remain unreproduced after bounded investigation; supervisor approved documenting those evidence gaps without speculative production edits. Syntax/diff checks precede z-commit; final independent review belongs to the parent. No deployment is needed for test-only changes.
