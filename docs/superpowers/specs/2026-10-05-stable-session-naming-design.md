# Stable Session Naming

## Goal

Keep the Pi session name stable while work contributes to the same broad goal. The name is a durable identity, not a task status.

## Approved guidance

Preserve the current name by default. Set a broad name once when the goal becomes clear, including when the initial automatic name is provisional. Rename later only for an explicit rename request or a clear switch to an unrelated broad goal. If the work still contributes to the existing goal, or the distinction is uncertain, preserve the name.

Related implementation, debugging, verification, deployment, and review retain the name. Recording, reporting, or briefly investigating an incidental finding also retains the name, even when the finding is unrelated. Resuming or recovering context does not reset naming. Preserve direct user names throughout related work. Most sessions should retain one agent-selected name for their lifetime.

## Scope

Update only the model-facing description of `set_session_name` in `roles/common/files/pi/extensions/managed-hooks.ts`. Keep initial automatic naming, the explicit rename skill, and the mutation interface unchanged. Keep the existing subject and outcome naming guidance.

## Verification

Run the existing managed-hook checks. Use the actual registered description in a model spot-check for related work, incidental reporting, an ambiguous request, a resumed session, an explicit rename, and a clear broad-goal switch. Apply with `bin/provision` and compare the deployed extension with the source. These checks verify installation and sample decisions, not a guarantee of future model behavior.
