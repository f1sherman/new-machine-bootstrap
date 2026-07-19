# PR review fix report

## Scope

Fixed the P1 session-row parsing defect in `tmux-attach-or-new` without changing restore or reservation policy. The tmux format now emits a nonempty `owner=` field, and the helper strips that prefix after tab-delimited parsing. The session name remains the final diagnostics-only field, preserving selection behavior for names containing tabs.

The stateful fake renders the helper-provided tmux format through its existing tmux variable substitutions. Therefore the new literal `owner=` prefix is retained exactly while an unset `#{@ghostty_attach_owner}` expands to an empty value, matching tmux behavior.

## RED

Added `test_unreserved_restored_session_named_zero_is_selected` to exercise a successful restore containing the sole unreserved session named exactly `0`.

```text
$ ruby tests/tmux-restore-startup.rb --name test_unreserved_restored_session_named_zero_is_selected
Run options: --name test_unreserved_restored_session_named_zero_is_selected --seed 5350

# Running:

F

Finished in 0.932514s, 1.0724 runs/s, 2.1447 assertions/s.

  1) Failure:
TmuxRestoreStartupTest#test_unreserved_restored_session_named_zero_is_selected [tests/tmux-restore-startup.rb:217]:
numeric session name must not be parsed as a live reservation owner.
Expected: "$2"
  Actual: "$3"

1 runs, 2 assertions, 1 failures, 0 errors, 0 skips
```

This proves the previous parser treated session name `0` as the reservation owner, accepted `kill -0 0`, and created session `$3` instead of selecting restored session `$2`.

## GREEN

Focused regression after the production fix:

```text
$ ruby tests/tmux-restore-startup.rb --name test_unreserved_restored_session_named_zero_is_selected
1 runs, 5 assertions, 0 failures, 0 errors, 0 skips
```

Full required validation:

```text
$ ruby tests/tmux-restore-startup.rb
12 runs, 91 assertions, 0 failures, 0 errors, 0 skips

$ bash tests/tmux-restore-diagnostics.sh
PASS  bounded tmux restore diagnostics

$ bash tests/ci-test-inventory.sh
PASS  every tracked test-like file is referenced by CI
1 passed, 0 failed

$ bash -n roles/common/files/bin/tmux-attach-or-new
# exit 0, no output

$ shellcheck roles/common/files/bin/tmux-attach-or-new
# exit 0, no findings

$ ansible-playbook playbook.yml --syntax-check
[WARNING]: No inventory was parsed, only implicit localhost is available
[WARNING]: provided hosts list is empty, only localhost is available. Note that the implicit localhost does not match 'all'
playbook: playbook.yml

$ git diff --check
# exit 0, no output
```

The existing tab-containing session-name regression remains unchanged and passes in the full 12-test startup suite.

## Files

- `roles/common/files/bin/tmux-attach-or-new`
- `tests/tmux-restore-startup.rb`
- `.superpowers/sdd/pr-review-fix-report.md`

## Residual risks

None identified. The parsing change is limited to a literal sentinel on the previously empty owner field; session names remain diagnostics-only and reservation liveness semantics are unchanged.
