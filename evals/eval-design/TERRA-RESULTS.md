# Terra eval-design pilot

The existing historical skill-pilot cases did not establish that any tested
lesson is unnecessary. Keep the current skill guidance.

## Method

On `openai-codex/gpt-6.1-terra`, the existing `skill-pilot` experiment ran two
synthetic writing cases under seven frozen conditions: the historical baseline,
the historical candidate, four single-lesson removals, and an empty-policy
control. Each condition produced one response per case, for 14 responses. The
runner used medium reasoning and a 6,000-token output limit. All generations
completed. The experiment tests historical skill excerpts, not the full current
skill, an agent session, or real repair behavior.

The task owner reviewed the anonymous response packet against its four stored
criteria before inspecting condition labels. This was a blinded manual review,
not an independent reviewer or calibrated semantic judge. A score of 2 on all
criteria is required to pass. The conservative review treated a plan that only
said to capture usage as partial when it did not also rule out treating cheaper
incomplete work as an efficiency gain. A different reasonable reading of that
criterion could change individual grades. The reviewed responses, scores, and
reasons are in [the scored record](records/terra-skill-pilot.json); the
[report](records/terra-skill-pilot-report.json) is generated from that record.

## Results and limits

Every condition scored 0/2 complete passes, with no incomplete generations.
All seven plan responses addressed the separate historical baseline. Several
omitted protected-change observations, used a second implementation request, or
did not explicitly connect token comparisons to completed work. Interpret-case
responses generally identified the evidence that snapshots missed, but none
fully met the criterion requiring both a scope warning and an explicitly
outcome-authorized replacement task. Some proposed only S0 versus S2, omitting
S1 from the next comparison.

No case passed in all conditions, so there is no matched successful token
comparison. This small historical-excerpt study cannot determine whether the
current deployed skill works or whether its individual instructions are needed.
It also does not measure safety in a live agent or authorize guidance removal.
A further study needs current full-session context and independently calibrated
scoring, especially for the token-reporting criterion.

Raw provider responses, frozen inputs, hashes, usage, and the anonymous review
packet remain in this worktree's ignored `tmp/terra-skill-pilot/`. Preserve them
before retiring the worktree. The checked-in scored record contains synthetic
answers and excludes usage for all failed responses.
