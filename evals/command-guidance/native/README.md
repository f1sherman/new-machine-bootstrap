# Native terminal-fragment reassessment

The pre-inference design and original harness are preserved at commit
`d05cc2ee668b89a2d53ed65c263460dc2d4a2306`. The design below is unchanged;
execution instructions now use the shared command template and calibration
launcher. `RESULTS.md` separates the original trials from verifier-only regrading.

## Benefit to Brian

Primary category: `time-saved`. Determine whether Brian still needs terminal
copy-paste guidance to avoid repairing long commands, without changing production
instructions on the strength of an excerpt-only experiment. This is a bounded
synthetic diagnostic, not a measurement of time saved.

## Frozen question and decision rule

Compare the complete current Pi base, that same base with only
`24-terminal-commands.md` removed, and an empty guidance file. Pi's built-in
prompt remains in all three. Use `openai-codex/gpt-6.1-terra`, medium reasoning,
12 maximum native turns, 180 seconds per candidate, 60 seconds per verifier,
two repetitions per case and condition: **36 initial paid trials maximum**.
Conditions rotate through the shared runner. No behavioral failure may be
rerolled. Infrastructure failures remain incomplete and stop execution.

Recommend **keep** if the current condition preserves usable commands while
removal introduces observed copy-paste policy failures. Recommend **inconclusive**
if failures or redundant safeguards prevent attribution. A possible **remove**
recommendation requires all tested safeguards to remain satisfied without the
fragment AND fresh confirmation; even that cannot authorize dropping uncovered
safeguards. A **revise** proposal must identify an observed burden/failure, retain
untested rules, and needs separate authorization and matched fresh testing before
claiming improvement. No production guidance changes in this study.

These criteria and the cases below were written before inference. Initial staging
freezes actual instructions, checks, infrastructure, guidance, and model settings.
See `RESULTS.md` for launch identities, evidence, and outcomes.

## Case provenance and rule coverage

All six are **reused synthetic task-only diagnostics**, not independent natural
incidents, stress tests, or unseen validation. The source is `../cases.json` from
commit e42527005c21267267eb1b117a67e3250f4e34e1. Six distinct cases avoid treating
repetitions as new case coverage. The common shell-code-block response contract
is presentation-only; tasks contain no width or wrapping reminders. The awk
fixture's contents are now supplied in the instruction as well as its file.

| Case | Observable task check | Rules exercised |
| --- | --- | --- |
| path-spaces | exact cat pathname, including spaces | 80 columns; quoted expansion; long assignment construction; no path continuation/newline |
| mixed-arguments | exact tool config/endpoint/dry-run arguments | path and URL; option=value integrity; long assignments; continuations at argument boundaries |
| quoted-value | exact message argument | literal data whitespace; long values; no quoted data newline |
| jq-program | real jq prints alpha and gamma | jq program whitespace exception; no heredoc; shell quoting |
| awk-program | real awk prints 13 | awk program whitespace exception; no heredoc; shell quoting |
| print-lines | real shell prints alpha and beta | shell construction; literal output; no heredoc |

Every answer is independently checked for task success, one nonempty shell
block, 80-character physical lines (including assignments), and absence of
heredoc syntax. Both Bash and Zsh must execute successfully. Manual transcript
review additionally checks variable names, quoted expansions, argument-boundary
continuations, literal newlines, and whether tool usage or prose changes the
interpretation. The mental final-check instruction is not directly observable;
only its consequences are. Literal `<<` data could trigger the conservative
heredoc screen and must be manually adjudicated with original scores retained.

Uncovered or weakly covered: bare key=value, JSONPath, regexes, actual visual
terminal wrapping, printf-based long-value construction, attempts to assign Zsh's
`path`, and newline corruption occurring in real usage. jq/awk examples are short,
so they permit but do not force multiline filters. No clause-specific necessity
claim is justified. Retain all these safeguards regardless of a null result.

## Fresh reserve (not yet run)

These three **new synthetic tasks**, absent from the old 18, are held back from
initial generation. Two repetitions per condition allow at most **18 additional
trials**, only for a removal recommendation or authorized tuning confirmation.
They require staged task fixtures and calibration before use, not another runner:

1. Show `/home/eval/Library/Application Support/Invoice Exports/quarterly/reconciled/2026-Q4/final ledger.csv` with cat. Exact pathname check.
2. Give a command for tool with `--endpoint=https://archive.example.net/api/snapshots/customer-billing/reconciled?quarter=2026-Q4&format=csv` and the literal argument `label=Quarterly invoice export for accounts with delayed settlement and manual review`. Exact arguments, normalize only endpoint equals/separate forms.
3. Use jq -r to print `customer + ": " + total` for paid invoices from input.json containing `{"invoices":[{"paid":true,"customer":"Ada North","total":"19.95"},{"paid":false,"customer":"Bo West","total":"7.00"},{"paid":true,"customer":"Cy East","total":"4.50"}]}`. Real stdout `Ada North: 19.95\nCy East: 4.50\n`.

Do not promote these into the initial selection after seeing results. If fresh
confirmation is unnecessary, keep them unrun and spend no additional inference.

## Grading and safety boundary

`study.toml` is consumed by `evals.runner.run`, not a package-specific model loop.
The shared command template supplies one Dockerfile, task settings, grading
entry point, argument stubs, and execution safeguards. Study assets supply only
the terminal-specific verifier and calibration cases. Individual cases contain
instructions, grading data, and any input fixture or build-time setup script.
Dependencies are installed at image build time. Candidate fixtures contain no
checks, labels, alternative guidance, or real services. The native agent remains
in Harbor's restricted UID1001 container with only the inference hostname allowed.

Harbor transfers native sessions into a **different, networkless verifier**.
Trusted root code parses the terminal reply, protects `/tests`, `/logs`, and
`/workspace` as root-only, and launches each generated command as UID1001 with
empty supplementary groups, zero effective capabilities, no-new-privileges,
resource limits, fresh scratch, and a credential-free environment. Only trusted
orchestration/inspection runs as verifier root. A separate pipe captures stub
arguments independently of stdout; real jq/awk/shell output is inspected directly.
Scores and checks stay inaccessible to the generated process. No candidate hooks
or scripts are imported by the grader. Symlinks in candidate artifacts are not
used as executables; only native JSON text is read.

The pipe is instrumentation, not an adversarially immutable audit log: a
cooperative generated program can inherit its write end. This study contains no
hostile task payloads and makes no tamper-proof-trace claim. Container escape
resistance and process-isolated inference credentials are shared-runner limits.
CLI argument equivalence is deliberately narrow: declared equals/separate option
forms and cat's optional `--`; not arbitrary CLI semantics. Stub stdout is not
real curl/tool behavior, and no request reaches a real service. The prior PR760
excerpt/component results are case history only, not native full-base evidence.

The shared `evals.runner.calibrate` launcher builds the pinned runtime and each
assembled task, then exercises its actual grader in a separate disposable
networkless calibration container: correct, wrong, equivalent-safe answers
for every case; stdout-transforming pipelines; separate width/heredoc failures;
UID/capability/privilege checks; denied reads/writes of criteria/results; denied
network; and the actual verifier entry point with a synthetic native session.
It performs no inference and never executes generated shell on the host.

## Commands

From this checkout, install the pinned Harbor environment as documented in
`../../runner/README.md`, then:

```bash
f=evals/command-guidance/native/study.toml
tmp/harbor-venv/bin/python -m evals.runner.calibrate --study "$f" \
  --output tmp/terminal-calibration

tmp/harbor-venv/bin/python -m evals.runner.run \
  --study evals/command-guidance/native/study.toml \
  --model openai-codex/gpt-6.1-terra --trials 2 \
  --output tmp/terminal-stage
```

Use a fresh output directory and `--live` only after calibration and design
review. Use only the supported access-only exporter of the existing Pi login.
Audit completed evidence with `--audit tmp/terminal-live`. Grader repairs use
Harbor verifier-only regrading of captured answers, preserving original scores.
Raw transcripts stay in ignored `tmp/` through review, not in Git. Compare usage
only for matched successful trials: Harbor input includes cached input as a
subset, never add cache again. Neither failures nor incomplete trials support
savings claims. Production guidance and old suites remain unchanged.
