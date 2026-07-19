# PR Review Fallback Fix Report

## Scope

Fixed the reviewed P1 without widening behavior: fallback login shells now inherit an explicit suppression marker, and both managed Debian dev-host login-shell handoffs honor it.

## RED

Added regressions before implementation:

- `test_attach_failure_clears_reservation_and_opens_fallback_shell` records the exec replacement environment and requires `TMUX_ATTACH_FALLBACK=1`.
- `test_managed_login_shell_handoffs_skip_tmux_fallbacks` requires both the managed `.zprofile` tmux auto-launch and `.bashrc` zsh handoff to include `[ -z "${TMUX_ATTACH_FALLBACK:-}" ]`.

Command:

```text
ruby tests/tmux-restore-startup.rb
```

Observed failure:

```text
13 runs, 90 assertions, 2 failures, 0 errors, 0 skips
TmuxRestoreStartupTest#test_managed_login_shell_handoffs_skip_tmux_fallbacks
  missing TMUX_ATTACH_FALLBACK guard in managed .zprofile block
TmuxRestoreStartupTest#test_attach_failure_clears_reservation_and_opens_fallback_shell
  Expected: "1"
  Actual: "unset"
```

## GREEN

Implementation:

- Export `TMUX_ATTACH_FALLBACK=1` immediately before the fallback shell `exec`.
- Require the marker to be unset before either managed login-shell handoff executes.

Validation:

```text
ruby tests/tmux-restore-startup.rb
13 runs, 97 assertions, 0 failures, 0 errors, 0 skips

bash tests/tmux-restore-diagnostics.sh
PASS  bounded tmux restore diagnostics

bash tests/ci-test-inventory.sh
PASS  every tracked test-like file is referenced by CI
1 passed, 0 failed

bash -n roles/common/files/bin/tmux-attach-or-new
passed

shellcheck roles/common/files/bin/tmux-attach-or-new
passed

ansible-playbook playbook.yml --syntax-check
playbook: playbook.yml


git diff --check
passed
```

Ansible emitted only its expected empty-inventory warnings during syntax validation.
