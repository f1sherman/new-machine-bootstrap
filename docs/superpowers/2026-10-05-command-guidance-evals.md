# Command guidance eval design and implementation plan

Approved scope: compare the old rule, current detailed guidance, compact rules,
and compact rules with one example. Use 12 development cases, three fresh
calls per case, and separate holdout cases. Select the shortest version only
after behavioral verification. Keep the 80-character and no-heredoc rules.

## Execution

Native execution in this session. Do not use implementation subagents.

## Files and responsibilities

- `evals/command-guidance/run.rb`: isolated Pi generation, sandboxed Bash/Zsh
  grading, failure reporting, and provider usage capture.
- `evals/command-guidance/cases.json`: prompts and expected observable arguments;
  development and holdout sets.
- `evals/command-guidance/variants/*.md`: four initial frozen candidates and
  three follow-up candidates informed by development and exploratory results.
- `evals/command-guidance/README.md`: reproducible commands, safety constraints,
  evidence, and limits.
- `tests/command-guidance-eval.rb`: execute the grader with real shell inputs;
  distinguish intact arguments, broken arguments, quoted literal newlines,
  meaningful jq/awk programs, formatting failures, and sandbox failures.
- Both managed base fragments: replace detailed guidance only if evals support
  the compact candidate.
- `tmp/command-guidance/`: ignored raw model streams, grader outputs, and usage.

## Tasks

- [x] Build behavioral grader tests first. Demonstrate that missing grading
  behavior fails, then implement it. Run real shells with harmless stand-ins
  under a macOS sandbox. Fail closed if the sandbox is unavailable.
- [x] Add 12 development cases covering paths, URLs, spaces, option values,
  JSONPath, literal values, jq, awk, and wrapping pressure. Add independent
  holdout cases. Freeze all four candidate texts before generating responses.
- [x] Generate one response per isolated Pi process without tools, extensions,
  context files, skills, saved sessions, or prompt templates. Keep model and
  reasoning settings constant. Save authoritative messages and actual usage.
- [x] Run three repeats of each development case for all four candidates.
  Report exact argument, formatting, program-result, and infrastructure failures
  separately. Check short candidates on holdouts without tuning to holdouts.
- [x] Select only a short candidate with no observed regression against detailed
  guidance. If none passes, retain the existing guidance and report failures.
- [x] Recheck deployed personal guidance after provisioning, including Codex's
  link to the Claude guidance.

Publication follows verification: commit source, evals, and the evidence summary,
then update the existing draft PR.

## Outcome

The first exploratory holdout exposed a Zsh variable-name regression. After
addressing it, six new validation cases were frozen before generating responses.
The selected 106-word candidate and detailed baseline both passed every fresh
validation case on both models. The selected candidate still had one development
failure; document it rather than claiming universal reliability.

Independent review found no merge-blocking issue. Its helper-file grader finding
was reproduced with a failing behavioral test, then fixed with a per-case
read-only sandbox. The final deterministic grader suite has 15 tests.

## Reviewer verification

Run `ruby tests/command-guidance-eval.rb` for deterministic grader checks.
Run the documented eval command to reproduce model generation and grading.
Review the result table and selected raw outputs under the ignored results path.
The committed README must report the actual model, repeats, measured input
tokens, failures, and limitations. These finite two-model evals do not prove
equal reliability across all models or real conversational contexts.

## Self-review

The runner checks generated command behavior, not document wording. Sandbox
checks prevent generated snippets from modifying the host or using the network.
Expected arguments include exact whitespace and option attachment. Infrastructure
errors are not counted as model compliance passes.
