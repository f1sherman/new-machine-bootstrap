# pir Herdr support

Status: self-approved under z-quick-pr.

## Goal and scope
Resume the exact Pi session bound to the current Herdr pane without tmux.
Keep tmux behavior and argument forwarding. Do not change Pi or Herdr integrations.

## Assumptions and evidence
Herdr 0.9.1 already reports result.pane.agent_session with agent=pi,
kind=path, and the absolute session path in value. The installed Pi integration
reports this for TUI sessions, not headless children. The live current pane
contains this binding. jq is available on provisioned hosts.

## Approach
Prefer the existing tmux binding when TMUX_PANE is present. Otherwise, require
HERDR_ENV=1 and HERDR_PANE_ID. Query `herdr pane get` using HERDR_BIN_PATH
when set. Use jq to accept only a matching pane with agent_session.agent=pi,
kind=path, and a nonempty absolute string path. Reject failed API calls,
malformed responses, absent/wrong-agent bindings, and missing session files.
Never fall back to directory-based resume or the other runtime after failure.
Keep `exec pi --session` and forward all user arguments unchanged.

## Alternatives
- Private binding files: unnecessary duplicate state with stale-state risk.
- `pi --continue`: may resume another pane's session; rejected.

## Verification and rollout
Run Bash syntax validation and temporary behavioral probes with inert Pi and
runtime commands for both runtime branches and error cases. Query the live
Herdr binding through the helper with only Pi launch replaced by an argument
recorder; this verifies the real API boundary without starting a second agent
in the active pane. Provision only the helper task using bin/provision and
repeat the live-boundary probe against deployed bytes. No retained automated
test: this small selector is covered by focused end-to-end verification.
No screenshots: the helper does not change rendered presentation.
