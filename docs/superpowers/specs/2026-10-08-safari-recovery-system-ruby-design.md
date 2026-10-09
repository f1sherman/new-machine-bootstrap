# Safari recovery on macOS system Ruby

Status: Self-approved

## Goal and evidence

Make the merged Safari recovery execute in Hammerspoon's actual environment.
The launch replay exited 1 before querying OmniWM. macOS `/usr/bin/ruby` is
2.6.10 and has a deprecated legacy Data class without Data.define. The helper
mistakes that constant for Ruby 3.2's Data API. A direct system-Ruby invocation
reproduced the same error. No windows moved during the failed replay.

## Approach and boundaries

Check Ruby's version before using Data.define; Ruby 3.2 introduced that API.
Keep the existing frozen Struct fallback for older Ruby. Do not change window
matching, wait limits, assignments, or the watcher. This is compatibility with
the current macOS runtime, not a third-party dependency patch.

Alternatives: forcing Hammerspoon's PATH to use mise Ruby adds a runtime
configuration dependency; removing Data entirely adds an unrelated model
rewrite. Select the minimal version check.

## Verification and rollout

Add a behavioral test that runs the production helper with `/usr/bin/ruby`
against the existing fake OmniWM IPC, and verifies scoped recovery succeeds.
Skip only when the system Ruby executable is unavailable. This catches the
actual entrypoint/runtime boundary that ordinary modern-Ruby tests missed.
Run it RED then GREEN, run recovery and watcher suites, and run system Ruby
against live IPC with --check. Commit and open a follow-up PR to #648.
Provision under the existing approval, then repeat the launch-callback replay
and require exit 0 with confirmed profile assignments. Do not crash Safari.
