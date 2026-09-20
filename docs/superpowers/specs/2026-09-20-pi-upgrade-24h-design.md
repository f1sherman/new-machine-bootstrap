# Pi upgrade and 24-hour release eligibility

Status: self-approved.

## Goal and scope

Upgrade managed interactive Pi from 0.85.1 to the latest stable release at least
24 hours old. Give future Pi updates a 24-hour Renovate age gate instead of the
repository-wide seven days. Preserve exact version pins, dependency safeguards,
review, and merge authority. Do not change service runtimes or frozen replay
images in HNP, refresh credentials, or claim that upgrading fixes Astra access.

## Evidence and assumptions

At 2026-09-20 23:16 UTC, npm latest is 0.86.1 (published 11:16 UTC that day).
0.86.0 was published 2026-09-19 23:14 UTC and is the latest eligible release.
The requested 24-hour wait applies to this upgrade too; do not exempt Pi from
Aube's release-age policy to install a younger version.

NMB owns the Pi pin and mise installation, including matching pi-server and
pi-client packages. Renovate currently has a global seven-day age and daily scan.
The current pin's mise minimum_release_age=0d is intentional: Renovate selects
reviewed exact pins, while Aube paranoid mode separately checks dependencies.
Retain this layered behavior rather than adding an inconsistent third gate.

## Approach

Recommended: pin 0.86.0, override minimumReleaseAge to 1 day for only the existing
custom.regex manager's @earendil-works/pi-coding-agent dependency, and run the
existing Renovate workflow hourly instead of daily. Other packages keep seven
days. Hourly scanning reduces eligibility discovery delay; it is not a promise
of installation at exactly 24 hours. Merge and normal provisioning remain gates.
No new daemon, auth, automatic merge policy, or Pi self-update path is added.

Alternatives: keep daily scanning (can add almost a day after eligibility), or
use floating latest installs (loses review and reproducibility). Neither meets
the requested freshness as well as an hourly scan with a scoped age rule.

## Verification and rollout

Validate the Renovate configuration using its validator and inspect current npm
release times. Validate YAML and render the managed version consistently for Pi
and its runtime companions. No configuration-presence test is retained under the
repository test-quality policy. Install through normal provisioning, preserve
running sessions, and verify the resulting CLI version and companion imports.
Aube may reject a newly published transitive dependency; do not bypass its policy.
Report any blocked live install separately from the completed source change.

Pi 0.86 introduces a TranscriptContext custom-provider contract. Review release
notes and verify available startup/extension boundaries without a live model call.
The frozen 0.85.1 replay adapter must remain pinned until a separate compatibility
change. Roll back by restoring the version pin and provisioning; never delete
sessions. Open the first-party GitHub PR and leave merge to Brian.
