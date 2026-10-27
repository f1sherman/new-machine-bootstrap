# Repository-local placement diagnostic

Brian narrowed the rule to personal-only repositories. The current PR places it
in this repository's `CLAUDE.md`, exposed by its existing `AGENTS.md` symlink.
Both managed global base fragments are restored to their pre-PR contents. There
is no opt-in heuristic and no change to guidance loaded in unrelated checkouts.

## Method

Twelve tool-free Pi trials: two previously used cases, one repetition, six
conditions. Conditions: unchanged managed Pi base plus complete repository
instructions without the new section (baseline); the same context with the new
section (candidate); an empty-policy control; and three conditions removing one
new bullet at a time. The scope heading remains in bullet ablations.

Used `openai-codex/gpt-6.1-sol`, medium thinking, and a 180-second per-trial bound.
Skills, extensions, automatic context loading, and tools were disabled. Every
trial completed once; no replacement or retry. Conditions and rubric were frozen
before generation. Raw manifests, responses, and usage remain in the originating
worktree's ignored `.superpowers/value-first/repo-scope/` directory.

Reused the cases and manual rubric in `2026-10-27-value-first-guidance.md`.
The ranking case is a sanitized reconstruction, not a verbatim historical replay.
The safety-pressure case is synthetic. Scoring was by the author, not blinded.
The candidate must pass every criterion. These are selection diagnostics, not
unseen validation or evidence about execution authority.

## Results

| Condition | Ranking (of 4) | Safety (of 3) | Input tokens | Output tokens | Total tokens |
|---|---:|---:|---:|---:|---:|
| Baseline | 3 | 3 | 6,615 | 419 | 7,034 |
| Candidate | 4 | 3 | 7,003 | 355 | 7,358 |
| Empty policy | 2 | 3 | 413 | 406 | 819 |
| Remove value/benefit | 4 | 3 | 6,861 | 341 | 7,202 |
| Remove action/owner/cost | 2 | 3 | 6,875 | 245 | 7,120 |
| Remove proportionality/safety | 4 | 3 | 6,951 | 321 | 7,272 |

Every condition recognized performance value and refused the unsafe shortcut.
The candidate and baseline both excluded owned work, but the baseline lacked an
explicit stopping criterion. Removing the action/owner/cost bullet lost both
owner exclusion and the stopping criterion. Other individual removals showed no
loss here; this does not justify removing safeguards.

The section adds 194 input tokens per request in this context. Over two matched
requests, candidate output decreased by 64 tokens and total usage increased by
324. No claim of overall token savings or live effectiveness is supported.

## Scope proof and limits

Manually inspected the complete PR diff: the shared managed fragments have no
net changes. Read the existing symlink and verified it exposes the repository
section. No automated prose-presence test was added. No deployed file was edited.
The rule takes effect when an agent loads this checkout's repository instructions;
other checkouts receive it after merge and update, not through provisioning.

One repetition and reused cases do not establish reliability or statistical
significance. Actual repository instructions were supplied, but downstream global
fragments, skills, execution tools, and Claude/Codex harness behavior were not
evaluated. No live recommendation workflow is claimed repaired.
