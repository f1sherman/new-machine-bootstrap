# Command guidance ablation protocol

Goal: test whether the selected guidance changes generated command behavior,
not only whether it matches another guidance version.

## Execution

Native execution. Use the existing isolated model runner and sandboxed grader.
Keep both managed guidance fragments unchanged during this experiment.

## Controls and factors

Freeze these candidates before generating responses:

- Full selected guidance: compact-portable.
- No guidance: an empty text file. The common coding-assistant system prefix
  and each user prompt remain identical to the full-guidance condition.
- No line limit: remove both explicit 80-character rules; keep other rules
  and the construction example.
- No heredoc ban: remove the heredoc ban; retain the visual-wrapping rule.
- No argument-boundary rule: remove the continuation-placement sentence.
- No long-value instruction: remove the length threshold, quoted-expansion
  instruction, and assignment-construction sentence. Retain the variable-name
  guard and example so this measures the prose's additional value.
- No quoted-newline rule: remove the quoted-newline sentence.
- No self-check: remove the shell-rejoining/check sentence.
- No portable-name guard: replace the named-variable guard with short variables.
- No example: remove only the construction example.

These are single rule-group omissions, not a factorial interaction study.
An omitted concept can remain implicit in other rules or user prompts. A null
result therefore means no measured incremental benefit under these conditions,
not that the omitted concept is universally useless.

## Runs

Use OpenAI gpt-6.1-sol and Anthropic claude-sonnet-4-6, reasoning medium.
Use three fresh calls per condition per case. Compare within each model only.
Interleave conditions through the runner's deterministic job shuffle. Save
raw streams, responses, measured input usage, and graded outcomes.

Start with the 12 unchanged development cases: 360 calls per model across
10 conditions. Run the unchanged six exploratory holdout cases afterward:
180 calls per model. No guidance edits or candidate tuning between these sets.
Previously used holdouts are diagnostic cases here, not new holdout evidence.

Many prompts already request 80-column formatting and exact data preservation.
Report this redundancy as a limit of the experiment. Do not add adversarial
prompts after inspecting results and count them as part of this frozen run.

## Analysis and artifacts

Record full versus no-guidance pass counts and failure categories: formatting,
argument/value changes, execution errors, program-result changes, and response
format. Report every ablation's count and per-case difference from full guidance.
Infrastructure errors are neither model failures nor compliance passes.

Save a separate ablation result artifact and add the measured table, exact
omissions, and limits to evals/command-guidance/README.md. Preserve prior results.
If an omission has no measured effect, say so. Do not claim statistical
significance from three possibly correlated provider responses.

## Completion

Run the deterministic grader suite, compare the captured summaries against
published counts, commit the experiment files and report, and update the
existing draft PR. Changes to guidance require separate evidence rather than
automatically deleting every clause with a null ablation result.

## Outcome

- Completed all 1,080 frozen model responses with no guidance tuning or rerolls.
- Full versus no guidance: OpenAI 54/54 versus 48/54; Sonnet 51/54 versus 23/54.
- Removing the construction example reduced Sonnet to 45/54. Several other
  omissions had no aggregate regression; this does not establish minimality.
- Corrected two false argument failures caused by stdout filters. Separate
  call logging also prevents forged stdout from hiding a wrong argument.
- Reproduced a process-group cleanup denial followed by an immediate no-group
  existence result. Cleanup verifies absence before accepting that denial and
  still rejects permission errors for existing groups.
- Regraded all 1,080 ablation responses and the 684 retained earlier responses.
  No final infrastructure errors; earlier per-variant pass counts unchanged.
- The deterministic suite passed 21 tests and 48 assertions.
- Kept managed guidance unchanged. Published exact omissions, summaries,
  representative responses, scoring corrections, and limits.
