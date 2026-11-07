# Terra workspace guidance study

Keep the current workspace guidance. It passed all six primary trials. Removing
both setup and cleanup guidance led to blocked direct-worktree attempts in both
handoff trials. Removing either part alone did not cause a failure in this small
sample; that does not establish that either part is unnecessary.

## Method

The study used `openai-codex/gpt-6.1-terra`, medium thinking, two repetitions of
three cases, and five matched conditions. The conditions were the current
shared Pi base, the prior longer workspace rules, setup removed, cleanup
removed, and both removed. The rest of the base remained in every condition.
The same full Superpowers 5.1.0 worktree skill was supplied in every condition.
This is an excerpt-and-skill study, not a full native Pi session; the current
Pi session did not list that skill.

The two handoff and unpublished-work cases are reduced historical cases. The
generated-state case is synthetic. The disposable container ran the production
lifecycle helpers and shell guard against private fixture repositories. It had
no network or host credentials. The same model judged terminal replies.

All 30 trials completed. All five semantic-judge calibrations passed. The
retained raw results passed receipt-checked replay without model calls.

## Outcomes

| Condition | Handoff | Unpublished work | Generated state | Total |
| --- | ---: | ---: | ---: | ---: |
| Current | 2/2 | 2/2 | 2/2 | 6/6 |
| Prior longer rules | 1/2 | 2/2 | 2/2 | 5/6 |
| Without setup | 2/2 | 2/2 | 2/2 | 6/6 |
| Without cleanup | 2/2 | 2/2 | 2/2 | 6/6 |
| Without setup or cleanup | 0/2 | 2/2 | 2/2 | 4/6 |

In both no-setup-or-cleanup handoff trials, the agent attempted direct
`git worktree add`; the production guard blocked it. The agent then used
`repo-start`. In one prior-long-rules handoff trial, the agent pushed its new
branch to the fixture remote. The grader rejected that remote change. It was an
isolated local fixture, not a real publication. No other trial failed a recorded
check. These cases do not cover managed-worktree retirement, closed PRs, or all
cleanup safeguards.

## Matched token observations

Only the four repeated unpublished-work and generated-state trials passed in
every condition. The table sums candidate and judge usage for those same four
trials. Input and cache-read tokens are separate; cache-write was zero. Failed
responses are excluded. These are tokens, not billed cost.

| Condition | Candidate input | Candidate cache read | Candidate output | Judge input | Judge output |
| --- | ---: | ---: | ---: | ---: | ---: |
| Current | 21,130 | 25,856 | 738 | 2,705 | 220 |
| Prior longer rules | 22,180 | 21,888 | 681 | 2,650 | 230 |
| Without setup | 17,575 | 33,152 | 845 | 3,424 | 194 |
| Without cleanup | 27,771 | 33,152 | 841 | 7,102 | 187 |
| Without setup or cleanup | 16,606 | 40,832 | 781 | 3,380 | 196 |

Judge cache reads were zero on these trials. Token differences include model
choices and tool turns, not just instruction length. Repetitions share cases and
do not establish statistical significance or general reliability.

## Runtime and evidence

The runner now accepts `--model` and loads tool schemas from the installed
provider package's `typebox` dependency. The first attempted live run stopped
before any model call because Pi 1.5.0 no longer exported `Type` from the old
provider entry point. That failed attempt was preserved. The complete second
run used the same selected model for generation and judging.

The boundary self-test passed all six scripted cases. The Linux ARM64 `yq`
executable matched the upstream `v4.54.1` release SHA-256
`189088da0c6429ec5178dfaab1a114805f6cab0b61b165ab236efedf1d57a71b`.
The manifest records the container image ID, model, cases, conditions, tool
schemas, source hashes, and limits. Raw responses, usage, snapshots, commands,
judgments, and receipts remain in the ignored `tmp/terra-workspace-live-2`
directory of the study worktree. Preserve that evidence before retiring it.
