# Session Naming Guidance Design

## Problem

Pi session names are not consistently useful in session pickers. Generated names can describe the current defect or implementation task instead of the overall reason for the session. For example, `Fix transient overlay replay` can hide that the session is about making Pi OpenAI compaction reliable.

A session name must help the user find the session later and remind them of its broad goal. Some session pickers truncate names, so the beginning of the name has the most discovery value.

## Requirements

A good session name answers two questions:

1. What recognizable system, initiative, or capability is this about?
2. What broad result is the session trying to achieve?

Use the preferred form `[recognizable subject] + [broad outcome]`.

- Preserve central subject terms from the user's request when they are clear.
- Put the most distinctive subject terms first.
- Make the first 31 characters useful for finding the session. Include the broad outcome in that prefix when practical. Treat later text as supplementary.
- Do not start with generic words when a recognizable subject is available.
- Choose an outcome that remains accurate through design, implementation, debugging, testing, review, deployment, and related follow-up work.
- Do not name the current symptom, implementation detail, ticket, phase, workflow, or next action.
- Do not use a repository name or identifier as the complete name. Keep it only when it is a useful part of the recognizable subject.
- Prefer a complete name of at most 40 characters. Preserve important meaning up to the hard 80-character limit. Do not create unclear abbreviations only to fit the discovery target.

Use this breadth check before selecting a name:

> If the current task disappeared from the transcript, would this name still describe why the session exists?

If the answer is no, the name is too narrow.

Examples:

| Request or context | Preferred name | Too narrow |
|---|---|---|
| Make the Pi OpenAI compaction extension reliable | `Pi compaction reliability` | `Fix transient overlay replay` |
| Improve Safari URL routing across windows | `Safari URL routing reliability` | `Ignore companion panels` |
| Make repository cleanup safer after merging | `Repository cleanup safety` | `Fix merge-proof callback` |
| Improve restore behavior for terminal workspaces | `Workspace restore reliability` | `Repair stale tab manifest` |

## Naming Lifecycle

The automatic child model continues to create a provisional name from the initial request. Its prompt uses the shared naming requirements.

The main agent makes one deliberate naming decision after it understands the initial top-level objective. It calls `set_session_name` even when a provisional automatic name exists. This lets the better-informed main agent correct a narrow provisional name.

The main agent keeps that name through all work that contributes to the objective. It calls the tool again only when the user starts a clearly unrelated top-level objective. Resume, handoff, scope refinement, implementation phases, debugging, testing, discovered defects, review, pull request work, deployment, and verification do not cause a rename.

A direct user rename is authoritative for the current top-level objective. The main agent does not overwrite it for related work. A later direct user rename or a clearly unrelated top-level objective can set a new name. The manual `z-update-session-name` skill applies the shared naming requirements without the automatic call threshold because the user explicitly invoked it.

## Approach

Align all three naming paths:

- the automatic initial-name child prompt;
- the `set_session_name` tool and parameter descriptions;
- the manual `z-update-session-name` skill.

This duplicates a concise decision model at three separate model inputs, but it keeps their output consistent. Updating only the tool would leave provisional and manual names inconsistent. Adding a second model review pass would add latency, cost, state, and nondeterminism without enough value.

Do not add runtime heuristics or an extra model call.

## Scope

Modify:

- `roles/common/files/pi/extensions/managed-hooks.ts`
- `roles/common/files/config/skills/pi/z-update-session-name/SKILL.md`

No other naming behavior or session state changes are in scope.

## Verification

No new automated test is required. A test that asserts exact prompt text would restate static configuration and would not verify model behavior.

- Run the existing managed Pi extension test suite.
- Run `bin/provision` from the feature worktree.
- Confirm the deployed tool and skill contain the intended naming and lifecycle guidance.
- Run the exact automatic naming prompt against representative initial requests.
- Confirm generated names front-load recognizable subjects, describe broad outcomes, and do not collapse into current implementation details.
- Confirm through tool guidance inspection that follow-up work keeps the existing name and a new unrelated top-level objective permits one rename.
