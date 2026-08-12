# Session Name Call Threshold Design

## Problem

The `set_session_name` tool guidance still permits frequent calls for related work. A session name should identify the broad session theme, not each task or phase.

## Design

Tighten the tool description in the managed Pi extension. Make **do not call** the default. Permit a call only when the user starts a new top-level objective that is clearly unrelated to the current objective.

Keep the existing name for follow-ups, scope refinements, implementation phases, debugging, testing, deployment, review, pull request work, and issues discovered while completing the current objective.

Do not add runtime heuristics or duplicate the rule in the global agent prompt. The model must make the semantic decision from the tool description at the point of use.

## Verification

Verify that the deployed tool description contains the new threshold and explicit exclusions. Run the managed Pi extension test suite and provisioning checks that cover the extension.
