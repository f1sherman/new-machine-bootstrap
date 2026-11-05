# Retire the terminal integration

## Outcome

Regular Ghostty tabs start the existing tmux shell instead of Herdr. Quick
terminal windows keep their login shell. This removes the unwanted first-tab
application without changing the tmux workflow.

## Scope and plan

- Remove launch helpers and the once-per-Ghostty-process decision.
- Keep `ghostty-tab-launch` as a small regular-tab/quick-terminal router.
- Remove Pi name synchronization with the retired terminal.
- Keep exact local Pi session recovery and tmux-based `pir` behavior.
- Remove the SSH tmux exclusion and retired integration-specific documents/tests.
- Provision the obsolete-helper removal. Do not stop running sessions or remove
  private state or session transcripts.

## Verification

Full laptop provisioning succeeded on 2026-11-04. A controlled execution of the
production Ghostty launcher selected tmux for a regular tab and the login shell
for a quick terminal, with no startup-state directory. Managed-hook checks pass
with the BB-only environment marker cleared for this standalone-Pi fixture.
A fresh-context review found no remaining issue in this repository.

The launcher execution is the safe boundary for Ghostty startup. No GUI window
was opened as part of this check. Existing terminal processes were not stopped.
