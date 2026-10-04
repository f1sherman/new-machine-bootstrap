# Pi external editor implementation plan

> Execute with superpowers:executing-plans in the current session.

Status: self-approved.

**Goal:** Make provisioned Pi select installed Neovim independently of its
launch environment.

**Architecture:** Add target-side executable resolution to the existing Pi
settings task. Merge the result into externalEditor.

**Tech stack:** Ansible, Pi settings, Neovim.

**Spec:** ../specs/2026-10-04-pi-external-editor-design.md

## Constraints and review focus

Preserve unrelated preferences. Fail if nvim is unavailable. Resolve on the
target, not the controller. Support check mode and repeated provisioning.
The executable location must not contain spaces because Pi splits its command
on spaces; this is already true of the supported installation paths.

## Task 1: Provision the editor setting

Files: roles/common/tasks/pi_main_worktree_guard_settings.yml and the existing
Pi settings provisioning fixture in tests/pi-main-worktree-guard-provisioning.sh.

- [x] Run the existing production task in an isolated agent directory seeded
      with externalEditor=vi and an unrelated preference. Confirm it keeps vi.
- [x] Add a read-only shell task using command -v nvim, register its result as
      pi_external_editor, set changed_when to false and check_mode to false.
      Prepend the target ~/.local/bin to its PATH. Gather facts in the existing
      provisioning fixture. Merge pi_external_editor.stdout into externalEditor.
- [x] Run the same task twice and in check mode. Expect an absolute nvim path,
      preservation of the unrelated preference, and no changes on the second
      run. Verify resolution fails when nvim is absent from the target PATH.
- [x] Load the rendered settings through Pi's SettingsManager. Run its
      editInExternalEditor with --headless -c wq while VISUAL and EDITOR point
      to vi and PATH excludes the Neovim installation. Expect unchanged prompt
      content and a successful exit with normal Neovim configuration.
- [ ] Commit the change and the completed plan. Invoke z-pull-request for final
      branch review, publication, and session-bound PR monitoring.

Use focused manual verification, not a new automated configuration test.

## Review result

Fixed the fresh-host PATH omission found by independent review. Verified the
production task with target PATH=/usr/bin:/bin after adding the managed binary
directory. The missing-Neovim check still fails visibly. Existing settings
provisioning coverage and full-playbook syntax validation pass.
