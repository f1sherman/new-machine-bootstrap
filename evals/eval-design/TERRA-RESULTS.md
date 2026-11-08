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

## Token-reporting experiment

A separate existing experiment tested the historical token-reporting candidate,
its baseline, the removal of its reporting lesson, and an empty-policy control.
Each condition answered three synthetic cases once. All 12 generations
completed. The task owner reviewed the anonymous packet against the frozen
criteria before inspecting condition labels. The candidate passed 3/3 cases;
the baseline, removal, and empty control each passed 1/3. In the overlapping-
and disjoint-success cases, all three non-candidate responses reported token
figures or totals containing failed responses. Each condition passed the
all-successful case.

On that single matched passing case, input/output tokens were 951/111 for the
candidate, 936/122 for baseline, 917/110 without the reporting lesson, and
103/118 for the empty control. These are model-reported tokens, not total billed
cost, and one case does not establish a general saving. This writing-only
experiment supports retaining the reporting lesson in this text-only context.
The candidate matched the installed `eval-design` skill byte for byte when
checked after the run. The skill is loaded on demand; this does not establish
full deployed-session behavior or evaluate the global startup instruction. The
[scored responses](records/terra-token-reporting.json) and generated
[report](records/terra-token-reporting-report.json) record the review and
comparisons.

Raw provider responses, frozen inputs, hashes, usage, and anonymous review
packets remain in this worktree's ignored `tmp/terra-skill-pilot/` and
`tmp/terra-token-reporting/`. Preserve them before retiring the worktree. The
checked-in scored records contain synthetic answers and omit usage for failed
responses.
