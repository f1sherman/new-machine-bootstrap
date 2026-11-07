# Terra terminal-command guidance study

Keep the current terminal guidance. Terra preserved the intended command
arguments and met the format checks on all 18 cases with the full excerpt. With
no excerpt, 13 commands exceeded the 80-character line limit. Individual
component removals passed most or all cases, but the remaining rules and example
can repeat the removed information. This sample does not establish that an
individual safeguard is unnecessary.

## Method

The study used `openai-codex/gpt-6.1-terra`, medium thinking, one response for
each of 18 task-only cases and ten conditions: full guidance, an empty control,
and eight single-component removals. Conditions rotated across cases. The host
Pi CLI had tools, sessions, context files, extensions, MCP, skills, and prompt
templates disabled. Generated commands ran only through the existing macOS
sandbox grader, in both Bash and Zsh. The host working-directory section differs
from the standard Harbor container driver, so this is a standalone excerpt
study, not a full session test.

All 180 model responses and grader invocations completed. Cases are synthetic
and emphasize long arguments. They are not workload frequencies or unseen
holdouts. The grader compares recorded argument lists and program output; it
does not establish general shell or command equivalence.

## Outcomes

| Condition | Combined pass | Functional pass | Format pass | Failed cases |
| --- | ---: | ---: | ---: | --- |
| Full guidance | 18/18 | 18/18 | 18/18 | none |
| Empty control | 5/18 | 18/18 | 5/18 | 13 long-line cases below |
| Without line-width rule | 17/18 | 18/18 | 17/18 | jsonpath |
| Without heredoc/visual-wrap rule | 18/18 | 18/18 | 18/18 | none |
| Without argument-boundary rule | 17/18 | 18/18 | 17/18 | jsonpath |
| Without variable-name rule | 18/18 | 18/18 | 18/18 | none |
| Without long-assignment rule | 17/18 | 18/18 | 17/18 | jsonpath |
| Without literal-newline rule | 18/18 | 18/18 | 18/18 | none |
| Without final-check rule | 18/18 | 18/18 | 18/18 | none |
| Without assignment example | 18/18 | 18/18 | 18/18 | none |

The empty control exceeded the line limit on `long-path`, `path-spaces`,
`long-url`, `long-option`, `jsonpath-equals`, `quoted-header`, `key-value`,
`quoted-value`, `mixed-arguments`, `path`, `url`, `jsonpath`, and
`quoted-option`. Its recorded arguments and program outputs still matched.
The three individual-removal failures also exceeded the line limit on
`jsonpath`; their recorded arguments matched.

## Matched token observations

Each row uses only cases passed by both full guidance and that condition.
Input and output counts exclude failed answers and grader processes. Cache read
and write counts were zero. Matching sets differ by row; totals are not directly
comparable across rows.

| Comparison | Matched cases | Full input / output | Comparison input / output |
| --- | ---: | ---: | ---: |
| Empty control | 5 | 1,410 / 124 | 505 / 124 |
| Without line-width rule | 17 | 4,818 / 779 | 4,495 / 861 |
| Without heredoc/visual-wrap rule | 18 | 5,111 / 819 | 4,985 / 937 |
| Without argument-boundary rule | 17 | 4,818 / 779 | 4,291 / 757 |
| Without variable-name rule | 18 | 5,111 / 819 | 4,625 / 836 |
| Without long-assignment rule | 17 | 4,818 / 779 | 4,478 / 790 |
| Without literal-newline rule | 18 | 5,111 / 819 | 4,679 / 973 |
| Without final-check rule | 18 | 5,111 / 819 | 4,751 / 923 |
| Without assignment example | 18 | 5,111 / 819 | 4,517 / 1,104 |

Only `jq-program`, `awk-program`, `print-lines`, `jq`, and `awk` passed in all
conditions. These token counts are not costs or a prediction for other tasks.

## Grader correction and evidence

The first grading marked one `jsonpath-equals` answer as functionally wrong
because it placed the global `kubectl -n production` option before `get` rather
than after the resource. The real `kubectl` accepted both forms in matching
help invocations. The grader now recognizes this narrow equivalent placement and
still rejects a changed namespace and an option after `--`. Its calibration
passed with 31 tests and 97 assertions. Regrading all 180 captured responses with the corrected grader
changed only that one result from fail to pass; no model response was regenerated.
The original scores remain in the raw run and in each regraded record.

A preliminary smoke test exposed Ruby's US-ASCII default in the host environment.
The same captured response passed after the grader was given a UTF-8 locale.
The grader now reads its request as UTF-8, and the same captured response also
passes under the original C locale. The runner sets a UTF-8 locale for its
credential-free grader process. The smoke attempt is separate from the frozen
matrix.

The runner checked all original trial receipts before regrading. Replaying the
original grader produced the same 180 outcomes. The original, replayed, and
regraded streams, manifests, assessments, and receipts remain under the study
worktree's ignored `tmp/terra-command-*` paths. Preserve them before retiring
that worktree. Hashes detect changes but are not signatures.
