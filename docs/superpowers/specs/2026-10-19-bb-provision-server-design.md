# One-time bb server selection

Status: approved by Brian in chat; personal/work prompt wording confirmed.

## Goal

Ask once for the bb server URL, save the choice, and reuse it on every
provisioning run. Personal machines select `https://bb.brianjohn.com`; work
machines leave the selection blank. No recurring flags, global personal-server
default, machine classification, or mutation of bb-owned settings.

## Context and selected approach

Commit `18a7ec4d` removed the personal/work prompt on March 19, 2026. Its
legacy config may still exist but is no longer authoritative. Do not revive
or infer settings from it. An optional per-run URL did not solve unattended
subsequent provisioning. Brian approved one-time URL selection instead.

Use a local Ansible action plugin only for enrolled Macs outside check mode.
It uses Ansible's native controller-side terminal API, prints instructions,
and accepts `1` for the personal URL, an explicit HTTP(S) URL, or blank for
work. It saves `{ "server_url": <string or null> }` atomically in
`~/.config/new-machine-bootstrap/bb-server.json` with mode 0600. Blank is a
saved choice, not an absent configuration. The action returns `server_url`
and `changed` for the command block. A saved choice never prompts again.

Ansible applies `BB_SERVER_URL` only for a non-null saved URL. Null preserves
the caller's environment and bb's normal settings. Keep `BB_CLI`, enrollment,
installation conditions, and command failure handling unchanged. Missing
configuration without a terminal fails with instructions to run provisioning
interactively. Invalid input, corrupt saved data, EOF, or interruption must not
silently save blank or overwrite an existing choice. Reject URLs containing
credentials, whitespace, query strings, or fragments. Check mode neither
invokes the prompt nor writes configuration.

Alternative: an Ansible pause task is smaller, but returns empty input when
stdin is noninteractive, which could accidentally persist a work choice.
The action catches noninteractive input explicitly rather than treating it as
blank. Command modules lack a controlling terminal, so the prompt must run on
the controller. Putting it in the shell wrapper would duplicate tag and
enrollment logic. Keep it scoped to the existing bb tasks. Print instructions
and the prompt to stderr so they remain visible through provisioning's stdout
log pipeline.

## Verification

Behavioral tests execute the action through Ansible with a real pseudo-terminal
and piped stdout, matching `bin/provision`. Cover personal
selection, blank work selection, custom URL, invalid input, saved-state replay
without a terminal, corrupt state, and interruption/noninteractive first run.
These tests protect persistent connection routing and refusal to guess; manual
provisioning cannot cover those state transitions. Add them to CI.

Run the original `bin/provision --tags bb` with inherited URL removed in a
pseudo-terminal and select personal once. Repeat without a terminal or flags;
require success, no prompt, and changed=0. Run check mode. Exercise work/null
selection in a temporary config with actual tasks, without contacting a work
server. No live work-server access is available.

## Progress

- [x] Investigate history and confirm approved design.
- [x] Implement and test saved selection.
- [x] Verify original workflow and repeat-run behavior.
- [x] Independent branch review; PR #688 tracks publication.
