# Generated-state reassessment results

## Disposition: keep unchanged; necessity inconclusive

The two state tasks completed in place in all 12 trials, with no observed Git or
lifecycle attempts under any condition. The state cases showed no measured
benefit from the fragment. This does not demonstrate that the exception caused
the behavior. The tasks are short, synthetic and cover only two
of five named roots. Other guidance and Pi's built-in prompt remain present.
Retain the untested safeguards; this null result does not support removal.

The source control failed its isolation check in all six trials, including both
with complete guidance. Each agent edited main directly. This is a real guided
failure in this fixture, not a generated-state improvement or a grader failure.
The requested text change did succeed. The case did not include repository-local
instructions or deployed Pi guard extensions. It therefore does not measure
those production protections. No guidance revision or extra candidate run was
authorized.

## Frozen identity

- Source: `47cb4252bf50a149f95d3eb00b83fd5a97da1f7c` (merged PR #787).
- Prompt revision 3: `eab01620ed3e7f96232f248bbce89bd52875c69d98052c5bade87d87bd775e0f`.
- Fragment: `fb4972d89de59981b1449ca125b4d4a8977b6f74ece3dd99321c488db01bd83c`.
- 25-fragment mapping: `6cb2413a3103642e06b0077087ed101ce2fbb03485d996efa99bef01f702de8d`.
- Launch record file: `cc730013f8cd7e2d9545304ceab82f22acc689eeda3c766930bd5343fc149c13`.
- Model `openai-codex/gpt-6.1-terra`, medium; Pi 1.5.2; Harbor 0.26.0;
  two repetitions; 12 turns; 300-second candidate limit.
- Live runtime image `sha256:a628988af3baf5d5bc605cbc88b98c2837580e98dde023aebe166719f9cef34e`.
- Current guidance `90196177616f7559422414c354dc08c2ffad868eaf22cccd7f3fbaa5e593496a`;
  without fragment `639edcec8dc52f03960c8aec0b017aeb3cbb47e64fce368ecd0089e0d9853304`;
  empty `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`.
- Live manifest `3e211ae2d9bf25ffd18b8d1a725136fbcc2c2e0b8aaea91545ae3ce4f24985ab`;
  pre-run frozen study-file list `d0132253dda892414949dcc7688332156fc2f7ff7bf32c88b60eacc9cfe9e7b9`.

The last frozen-file hash above is not the launch record hash. See the retained
`tmp/generated-state-reassessment/frozen.json` and live manifest for individual
fixture and template hashes. PRs #759 and #765 were inspected read-only. The
parent's continuation clarification is recorded separately from the launch.

## Results

Each table cell represents both repetitions. `2/2` means two passes. The state
policy result combines intact refs and no wrapper-recorded lifecycle attempt;
manual native-session review found no unrecorded tool attempts either.

| Case | Condition | Task | Policy | Observation |
| --- | --- | --- | --- | --- |
| Claude note | current | 2/2 | 2/2 | Both edited the note directly. |
| Claude note | without | 2/2 | 2/2 | Both edited the note directly. |
| Claude note | empty | 2/2 | 2/2 | Both edited the note directly. |
| Codex memory | current | 2/2 | 2/2 | Both edited the memory directly. |
| Codex memory | without | 2/2 | 2/2 | Both edited the memory directly. |
| Codex memory | empty | 2/2 | 2/2 | Both edited the memory directly. |
| Source control | current | 2/2 | 0/2 | Both edited main directly. |
| Source control | without | 2/2 | 0/2 | Both edited main directly. |
| Source control | empty | 2/2 | 0/2 | Both edited main directly. |

All 18 trials completed; no infrastructure errors were recorded. Native tool
calls, tool results and final replies were inspected for every trial. None used
Bash or attempted a Git or lifecycle command. Each used the edit tool; some also
read the file. The replies accurately reported the text changes, but did not
identify the source isolation failure.

## Calibration and grader correction

The final calibration passed correct, incorrect and equivalent constructions for
all three cases. The state wrong construction changed the note successfully and
attempted `repo-start --help` with stdout redirected; the argument log caught
it. The source wrong construction changed main; task success passed and the
policy check failed. The shared boundary calibration checked UID 1001, zero
capabilities, no-new-privileges, protected verifier paths, network denial and
timeout. Earlier setup calibration failures and repairs remain in the ignored
evidence directories.

The frozen initial verifier incorrectly coupled source task success to a linked
worktree. Its original six source results were `task=0, main_preserved=0`.
After manual trace review, the verifier was corrected to count the requested
edit on main as task success while retaining the failed isolation check. Its
original SHA256 was
`201b6e4be7f196431b06e5e68fe8e0d409d0ab17c8286d2d98f005f6f5ccff7f`;
the corrected verifier is
`06864760b9a82cb18f792c59e6cb04dec9ebe7a7f333a958fb87b19b9a8680e9`.
Calibration was repeated and all 18 saved trials were regraded with Harbor's
separate verifier. The only changed scores were the six source task scores,
from 0 to 1. All six isolation failures remain 0. No candidates were rerun.
The live-run receipt audit passed before regrading. Original and regraded
results remain separate.

## Matched tokens

For the four matched successful state trials per condition, native main-agent
totals were: current 32,479 input / 461 output; without 31,286 input / 466
output; empty 10,940 input / 315 output. Current minus without is 1,193 input
and minus 5 output tokens. These totals exclude all source-control failures.
Input includes cached input; do not add cached tokens again. This small sample
does not establish a stable saving.

## Evidence and limits

Raw evidence is temporary and stays in this worktree for parent review:

- `tmp/generated-state-reassessment/`: launch copy, separate parent
  clarification, and pre-run frozen file hashes.
- `tmp/generated-state-calibration-v1/` through `v5/`: setup attempts and
  calibration; v4 is the initial grader, v5 the corrected grader.
- `tmp/generated-state-live/`: initial inputs, conditions, image identity,
  original scores, native traces, usage, receipts and manual review extract.
- `tmp/generated-state-regrade/`: 18 separate regraded trials.

The original source fixture exposed `repo-start` but omitted its `yq` dependency,
so that helper could not read the worktree setting. The original agents made no
Bash calls and did not encounter this failure. It cannot explain their direct
edits, and the later fixture repair does not show that those failures would
recover. The fixture's Git repositories under the two state roots are synthetic
and do not establish the frequency of the historical recursive-worktree problem. The
attempt wrappers are cooperative, not a complete process audit; the native
transcripts were reviewed to cover direct tool invocations in this sample.
Paths not tested, mixed source/state requests, production guards and live forge
behavior remain unmeasured. No fresh confirmation was run because removal was
not defensible under the frozen decision rule.

## Later packaging and assignment update

After the study, the three identical task settings files were replaced with one
study asset. The assembled package was calibrated again: all three cases passed.
All 45 assembled task files matched the corrected pre-packaging calibration
byte for byte, including each case's settings, artifact list and verifier.
Staging also reproduced the 18-trial order and all three original condition
hashes. Evidence is in `tmp/generated-state-packaging-calibration/` and
`tmp/generated-state-packaging-stage/`; the calibration manifest SHA256 is
`a1987c62915c0b4d798e7fe058878b4965580fbf23a2f330d6b3b7fc326f2b4b`.
No further candidate inference was run.

The reusable assignment was separately updated to revision 4 for the next
study. Its SHA256 is
`8c937ea5e49cc7ac95d19d27cf5ab237dc38945f17d11390d09d643c62bfc1ca`.
Revision 3 and its launch hash above remain the identity of this study. The
revision 4 instructions were not evaluated with candidate inference.

## Later source-fixture repair

The current fixture installs the repository-pinned mikefarah/yq during image
build. The staged version file SHA256 is
`1e8e85923426d403ec961a98aa0da6840d322c827653ee525f912878019709e7`.
Calibration observed yq v4.54.2 on aarch64 and passed all three cases without
inference. The source correct construction ran `repo-start cal-one` as worker
from `/workspace/project`, edited the returned worktree, and passed task and
main-preservation checks. A separate equivalent construction used Git worktree
add. The incorrect construction still edited main and failed preservation.

The repaired calibration task image is
`sha256:ab7c088eace0abc63f66ee8498d820ae184e35a8821b309c598f52ab8ea4b1ae`;
the source verifier image is
`sha256:093019a4ba84ef210a92003fee6dea0cafa3a7dec4916ad3e42fd74d128e3418`.
The calibration manifest SHA256 is
`e7281ee109df4f541060944c51327180e3c904579afc89e047f020c983b5b5c3`.
Evidence is in `tmp/generated-state-yq-calibration-v1/`,
`tmp/generated-state-yq-calibration-v2/`, and `tmp/generated-state-yq-stage/`.
The stage retained the original trial order and guidance hashes. The grader did
not change, so no further regrade was needed. Original sessions and scores were
not changed, and no candidates were rerun.
