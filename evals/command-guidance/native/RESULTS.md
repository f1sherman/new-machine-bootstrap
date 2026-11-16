# Terminal fragment: native Terra reassessment

## Disposition: keep, with a recorded adherence gap

Keep `24-terminal-commands.md` unchanged. In the matched native study, the
fragment prevented overlong path/URL commands in four responses that failed
without it. It did **not** reliably handle long literal messages: both guided
responses still exceeded 80 columns. This supports retaining the tested width
and value-construction safeguards, not claiming that every clause is necessary
or that the fragment guarantees compliance. No revision was tested or applied.

Brian's benefit is fewer long commands to reformat for copying. Actual terminal
paste failures, repair time, and argument corruption were not observed here.
All commands remained functionally correct, including the overlong ones.

## Frozen launch and execution

- Source/branch: `e42527005c21267267eb1b117a67e3250f4e34e1`, `reassess-terminal-fragment`.
- Launch prompt revision: **1**, preserved at
  `d05cc2ee668b89a2d53ed65c263460dc2d4a2306:evals/fragment-reassessment.md`.
  The current file is revision 2 for the next assignment; it is not the prompt
  used for these trials.
- Prompt SHA256: `0beccffdce44095c6e2e1ba3003f850a3bf273d69d6c67ae846a4a33ba3fbe01`.
- Inventory SHA256: `6cb2413a3103642e06b0077087ed101ce2fbb03485d996efa99bef01f702de8d`.
  This hashes Python `json.dumps(fragment_hash_mapping, sort_keys=True)` with
  default separators and no trailing newline, not the launch metadata file.
  All 25 individual hashes were verified before work.
- Selected fragment SHA256: `d5c85e2857a8df6e91c1679b32178cfc193e3596dd5e4737e7c9d8a6164f4c69`.
- Frozen design README SHA256: `61d4f00e194625b2da1843f2d3c366395525c8c3ca921e95adeae779811092c5`.
- Verifier SHA256: `9d1d79aa16fa52e9d8b1ffdc2d1451b3a3a4fd1198c06aa27d8dd7345e204408`.
- Model: `openai-codex/gpt-6.1-terra`, medium reasoning; native Pi **1.5.2**,
  Harbor **0.26.0**, shared runner unchanged. Existing access-only login export;
  no new credentials, deployed config changes, or real service side effects.
- Runtime image: `sha256:a628988af3baf5d5bc605cbc88b98c2837580e98dde023aebe166719f9cef34e`.
- Run owner: `5eb36a64-1ddf-49dc-b9cd-683b91f7ab5b`.
- Manifest SHA256: `b2dabbdd4f7d1d383e91c4776688a4110ef2f15416da8ebdf357c94bdc920f65`.
- Assembled guidance SHA256:
  - current: `90196177616f7559422414c354dc08c2ffad868eaf22cccd7f3fbaa5e593496a`;
  - only-fragment-removed: `fcd24a0335a62bffe6589aea81ca80632af8dc6d2f30ccc5743c261121e094c8`;
  - empty: `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`.

The README froze six reused synthetic cases, checks, bounds, three unrun fresh
reserves, and the keep/remove/revise/inconclusive decision criteria before paid
calls. Two repetitions per case per condition produced **36/36 complete trials**,
zero infrastructure failures, and no rerolls or verifier repairs. The 18-trial
fresh reserve was not used: removal is not recommended and no tuning was done.
The shared runner's final nonzero exit is the expected current-guidance failure
signal, not an incomplete matrix. Offline audit passed.

## Original problem and remaining safeguards

History introduced 80-column copy-paste commands in `35909e3e`, prohibited
heredocs in `0a520a59`, and consolidated the construction/argument rules in
`3a512837` (#631). These changes express a real formatting preference and
protection against malformed pasted values; Git history alone does not establish
a measured frequency of terminal incidents.

| Rule | Harm or effort avoided | What this sample says |
| --- | --- | --- |
| Every physical line, including assignments, at most 80 columns; no visual wrapping | Manual reformatting or relying on terminal display wrapping | Clear guided advantage on paths/URLs; literal-message gap remains; no real terminal tested |
| No copy-paste heredocs | Multiline paste/termination mistakes | All conditions avoided them; necessity unresolved |
| Continuations only between complete arguments, preserving indentation when joined | Spaces or newlines corrupting paths, URLs, options, or data | All actual arguments intact; one guided continuation was correctly placed; little failure exposure |
| Store long arguments in f/url, quote expansions, never assign Zsh's path | Unwanted word splitting and accidental PATH mutation | Guided path/URL cases used f/url correctly; guided literal messages did not use the required construction |
| Build overlong assignments from short pieces or printf | Moving the width problem into an assignment | Guided path/URL cases used short successive assignments; printf construction not exercised |
| Literal quoted newlines only as jq/awk program whitespace | Silent newline bytes in names/data | No corrupting newlines; candidates used single-line jq/awk, so the exception's necessity is untested |
| Final mental continuation/argument check | Catch malformed commands before sending | Internal checking is not observable; only intact execution and width can be checked |

Other base fragments encourage short writing, directness, verification, and
retaining untested safeguards; none supplies the explicit 80-column rule.
Native Pi's built-in prompt and tools remain present in every condition.
Functional correctness without this fragment suggests ordinary quoting/program
construction was already available on these tasks, not that the risk-specific
safeguards are obsolete. Retain uncovered bare key=value, JSONPath, regex, Zsh
path, printf-construction, visual-wrapping, and literal-newline protections.

PR #760 (`terra-command-guidance`) was inspected read-only as case/measurement
history. Its 180-response standalone excerpt/component study disabled native
tools and full base context; its 18/18 guided result is not pooled with this
study or used as full-base necessity proof. Neither that PR nor its branch was
changed. Other eval workstreams were untouched.

## Reviewed results

Every native tool call, result, and terminal reply was read against the actual
Bash/Zsh observations. Each table cell contains the two native repeat indices
**0, 1**, in that order. `P` means task, answer format, width, and heredoc checks
all passed; `W` means **width only failed**, while task/format/no-heredoc passed.
Numbers in parentheses are maximum physical command-line widths, including
assignments. All **36 tasks succeeded in both shells**, with zero stderr and no
timeouts; all 36 returned one nonempty shell block and no heredoc.

| Case | Current | Without fragment | Empty | Reviewed observation |
| --- | --- | --- | --- | --- |
| awk-program | P, P (66, 66) | P, P (58, 62) | P, P (58, 66) | Real awk printed `13` in every shell; no tool calls |
| jq-program | P, P (69, 69) | P, P (69, 69) | P, P (69, 69) | Real jq printed alpha and gamma; no tool calls |
| mixed-arguments | P, P (66, 61) | W, W (247, 247) | W, W (247, 247) | Exact config/URL/dry-run arguments in every shell; only current used short f/url assignments; no tool calls |
| path-spaces | P, P (58, 58) | W, W (96, 96) | W, W (96, 96) | Exact pathname including spaces; only current used short f assignments; no tool calls |
| print-lines | P, P (24, 24) | P, P (24, 24) | P, P (24, 24) | Real printf printed alpha and beta on separate lines; no tool calls |
| quoted-value | W, W (105, 92) | W, W (105, 105) | W, W (105, 105) | Literal message intact; native bash called harmless tool in both current, both empty, and without repeat 1; without repeat 0 returned advice only |
| Combined pass | **10/12** | **6/12** | **6/12** | Six distinct cases, not 36 independent cases |

The two current failures are native trial indices **16 and 33**. Index 16
returned the original 105-character command after a successful tool invocation.
Index 33 broke between `--message` and its value, but the quoted literal line
still contained 92 characters. Both also missed long-value variable construction.
There was no unsafe continuation, unquoted expansion, path-variable assignment,
or literal-data corruption. Tool execution itself is not subject to the
user-copy-paste width rule; the **final returned commands** are the failures.

The initial progress update estimated the first failure as 103 characters;
reviewed measurement corrects that to **105**. No score changed. There are no
superseded trial scores: all original failures remain in the report.

## Matched successful usage

Only the six complete **combined-pass** matches per comparison are included:
awk, jq, and print-lines, each twice. Path/URL and message usage is deliberately
excluded because the alternatives failed policy. Each cell is **input / output /
cached input**, from Harbor's native main-agent usage. Cache is a **subset of
input**, never added to it. These are not judge costs, billing estimates, or a
prediction of savings on Brian's workload. No paid judge was used.

| Case | Repeat | Current | Without | Empty |
| --- | --- | --- | --- | --- |
| awk-program | 0 | 2445 / 30 / 0 | 2260 / 29 / 0 | 1191 / 29 / 0 |
| awk-program | 1 | 2445 / 30 / 0 | 2260 / 30 / 0 | 1191 / 30 / 1024 |
| jq-program | 0 | 2468 / 29 / 0 | 2283 / 29 / 0 | 1214 / 29 / 0 |
| jq-program | 1 | 2468 / 29 / 0 | 2283 / 29 / 0 | 1214 / 29 / 0 |
| print-lines | 0 | 2422 / 16 / 2304 | 2237 / 16 / 2048 | 1168 / 16 / 0 |
| print-lines | 1 | 2422 / 16 / 2304 | 2237 / 16 / 0 | 1168 / 16 / 0 |
| Total, identical matching set | 6 | **14670 / 150 / 4608** | **13560 / 149 / 2048** | **7146 / 149 / 1024** |

## Calibration, safety, and verification

Before inference, calibration executed correct, wrong, and equivalent-safe
commands for every case in both shells (18 constructions). Real jq/awk/shell
outputs and independent stub arguments were checked. Output-transforming
pipelines did not alter argument measurement; wrong arguments remained failures.
Width and heredoc failures were distinguished from functional correctness.
The actual verifier entry point parsed a synthetic native session and produced
expected rewards. UID1001, zero effective capabilities, no-new-privileges, denied
reads/writes of checks/results, denied root recovery, and denied network were
probed inside the grading container. All 36 actual native agent boundary checks
also passed.

Calibration v1 passed; v2 additionally made the calibration-only `/opt/cases`
directory root-only before generated execution. After the matrix, v3 repeated
calibration with output-path containment validation in the host build helper;
the verifier and grading image were unchanged. All three records remain in tmp.
The live verifier never contains that calibration-only directory. A preliminary
UID-drop probe under the **agent** capability overlay failed as expected; pinned
Harbor clears that overlay for its separate verifier, where UID drop succeeded.
This was setup investigation, not a failed candidate trial or weakened isolation.

Commands completed:

- `evals/command-guidance/native/calibrate.sh tmp/terminal-calibration-v1`,
  `... tmp/terminal-calibration-v2`, and `... tmp/terminal-calibration-v3`:
  passed; v2/v3 grading image
  `sha256:02ae6ac5b4fc0d492ff8e7ebe166b5fe5cd69b472e0b02a926fc284ac4a6b306`.
- `tmp/harbor-venv/bin/python -m unittest evals.runner.test_runner`: 2 tests passed.
- Shared runner stage with `--study evals/command-guidance/native/study.toml
  --model openai-codex/gpt-6.1-terra --trials 2 --output tmp/terminal-stage-v1`:
  staged 36, no inference.
- Same runner/settings with `--output tmp/terminal-live-v1 --live`: all 36 complete;
  final nonzero due to the two retained current-guidance behavioral failures.
- `tmp/harbor-venv/bin/python -m evals.runner.run --audit tmp/terminal-live-v1`:
  receipts, frozen inputs, native results, and matched summary verified offline.
- `git diff --check`: passed. Production guidance and all launch fragment hashes
  remain unchanged. No provisioning or publication was performed.

Temporary evidence, relative to this checkout:

- `tmp/reassessment-launch-v1.json`: launch metadata and all 25 hashes.
- `tmp/terminal-stage-v1/`: initial frozen staging.
- `tmp/terminal-live-v1/`: frozen tasks/guidance/infrastructure, manifest, report,
  summary, receipts, and all 36 Harbor jobs. Each report row names its exact job;
  native `agent/pi.txt`, session artifacts, `boundary.json`, and
  `verifier/assessment.json` remain available for review/regrading.
- `tmp/terminal-live-v1/reviewed-extract.json`: temporary text/tool/observation
  review extract, without provider reasoning; not a replacement for native logs.
- `tmp/terminal-calibration-v1/`, `tmp/terminal-calibration-v2/`,
  `tmp/terminal-calibration-v3/`, and `tmp/verifier-setuid-probe.txt`:
  retained development/calibration evidence.

Raw transcripts/credentials/provider reasoning are not checked in. Raw evidence
is temporary through parent review and any needed regrading; it may expire with
worktree retirement. The committed package can run a new sample, not replay an
expired original.

## Limits and next-prompt corrections (separate from frozen v1)

This small, reused, synthetic long-value sample does not establish workload
frequency, statistical significance, minimal guidance, or clause-specific
necessity. Short jq/awk programs did not force the multiline exception.
Argument stand-ins measure declared argument equivalence, not arbitrary CLI
semantics. Instrumentation is stdout-independent but not a hostile-program-proof
audit channel. The study did not contain adversarial payloads. Natural full-base
references to prompt evaluation remain visible; perfect blinding is not claimed.
The full keep decision rests on observed path/URL differences, not null outcomes
under redundant safeguards. No missing shared capability blocked this study.

For the next reusable prompt revision:

1. Specify inventory hash canonicalization separately from the metadata-file
   hash, and verify every supplied fragment hash before work.
2. Preserve a neutral final-command output contract when migrating task-only
   cases. Native tools can execute imperative requests before replying; review
   those tool results **and** the final copy-paste command. Native behavior can
   differ from clean excerpt-only results, as both guided literal failures show.
3. State which rules were exposed versus merely permitted. Short programs that
   never used multiline syntax do not establish the newline exception's value.
4. Calibrate independent arguments and real stdout separately; protect verifier
   checks, results, native artifacts, and calibration fixtures before UID drop.
   Inspect the actual separate-verifier policy, not just the agent overlay.
5. Do not spend holdout calls when keeping already follows from matched failures.
   Retain guided failures as adherence gaps; do not silently tune or reroll them.
6. **Execution ownership correction:** the initial child improperly started the
   task-owned runner as an untracked shell background process (PID37519). The
   child hit the orchestrator's 30-minute default while that exact process kept
   running under PPID1. Parent authorized one bounded same-method recovery,
   which adopted run owner `5eb36a64-1ddf-49dc-b9cd-683b91f7ab5b`, foreground-polled
   its remaining trials, and did not launch or repeat inference. PID37519 exited
   after all 36 results were collected. Future launches must use a registered
   foreground/job mechanism and a timeout covering build plus the whole matrix;
   timeout recovery must inspect/adopt the exact existing owner before any new
   calls. This recovery amendment does not rewrite prompt revision 1 or its hash.

Parent review confirmed all 36 terminal answers and native tool calls against
these outcomes, repeated calibration in `tmp/terminal-parent-calibration`, and
passed the offline audit and runner tests. The reusable prompt is now revision 2
with the corrections above; the original launch hash remains revision 1.
No production change, extra inference, other fragment, or provisioning followed.
