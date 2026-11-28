# Report-writing guidance: keep the prior wording

**Question:** Does the revised prompt make the case, grading rule, and decision clear without changing the source facts? In two synthetic cases, the revised prompt passed the report rubric in two of four draws, one per case. None of the four reports using prior guidance passed the full rubric. The museum reports under prior wording did not tie the pass rules to each card early enough; both prior catalog reports included usage for failed or incomplete trials. Two revised reports hid effective judge settings in a disclosure. One matched prior report exposed both settings and the operative rules without opening a disclosure, so its revised mate regressed on the method criterion. Keep the prior guidance. These are small, supplied-evidence drafting trials, not a test of hosting, full skill discovery, or a human reader's speed.

- **Wording:** [prior](prior/report.md) and [revised](revised/report.md) are the exact frozen excerpts. Deletion keeps the common writing line and removes the reporting text. Empty keeps Pi's built-in context only.
- **Exact request for both cases:** “Make an HTML review report from the saved eval results in evidence/. Save it as report.html, then finish with a short reply. The reviewer handles browser checks; no browser work or publication is part of this task.”
- **Cases:** [Museum labels](tasks/museum-labels/environment/evidence/) tests reporting model grades on ambiguous versus clear cards. [Seed catalog](tasks/seed-catalog/environment/evidence/) tests separate code and model grades, a same-reply regrade, invalid grader output, and usage restricted to successes. These are synthetic task bundles seen during development. #793 is calibration only.

## What graded the reports

| Method | Artifact and passing rule | Limit |
| --- | --- | --- |
| Deterministic Harbor checks | Saved HTML: title/body and inert surface; verbatim prompts, guidance and available outputs; stable IDs. Catalog adds expected successful-trial counts and rejects distinctive failure/incomplete counts. Ordinary supporting anchors are allowed; resources that load automatically are not. | Presence does not establish visibility, meaning or the correct row. |
| Author review plus deterministic browser checks | Rendered HTML: per-case methods and rules (M), decision and limits (D), correct ledger (L), fidelity including source and usage (F), and delivery (A). Any material defect fails the full rubric. Browser: offline, scripts disabled, 390/1050 CSS px; check clipping and keyboard disclosures. | The author knows the study; the reports were inspected under opaque IDs. No blinded human readability measurement. No paid judge scored these reports. |

48 distinct offline vectors matched, including relative-anchor and resource distinctions, exact prompts, and usage leaks; 34 validation vectors were repeated for the prior block. A separate blinded AI source pilot distinguished two valid reports from four broken samples; browser calibration checked rendering. The exact v4 catalog artifact again failed private usage offline, without a candidate rerun or a changed v4 score. See [rubric and procedure](REVIEW.md).

## Matched outcomes

Pass means both the literal checks and the rendered-review rubric passed. Defects are listed in the appendix by stable artifact ID. All 16 rows had valid measurements, although 14 were scored behavior failures. There were no incomplete v5 rows.

| Case / repeat | Prior | Revised | Deletion | Empty |
| --- | --- | --- | --- | --- |
| museum-labels / 1 | [Page-01](#page-01) Fail | [Page-12](#page-12) Pass | [Page-04](#page-04) Fail | [Page-03](#page-03) Fail |
| museum-labels / 2 | [Page-05](#page-05) Fail | [Page-08](#page-08) Fail | [Page-10](#page-10) Fail | [Page-06](#page-06) Fail |
| seed-catalog / 1 | [Page-02](#page-02) Fail | [Page-09](#page-09) Fail | [Page-13](#page-13) Fail | [Page-16](#page-16) Fail |
| seed-catalog / 2 | [Page-15](#page-15) Fail | [Page-07](#page-07) Pass | [Page-11](#page-11) Fail | [Page-14](#page-14) Fail |

**Decision threshold not met.** Each case had a matched full pass repairing a prior defect (museum repeat 1 and catalog repeat 2), and deletion had the same material defects. But catalog repeat 1 regressed on the method criterion: the prior report exposed the effective judge settings and operative rules without opening a drawer; its revised mate did not. The frozen no-regression rule rules out adoption. Keep the existing guidance. A future revision should put effective judge settings beside the visible pass rules; it would need a new matched test.

### Successful trial usage

Only two revised reports passed the whole rubric, so there is no matched-success token comparison. Counts include cached input, once. No paid judge usage.

| Report | Candidate input | Candidate output |
| --- | ---: | ---: |
| Page-07 | 55,283 | 6,422 |
| Page-12 | 36,855 | 5,000 |

## Evidence appendix

Full candidate HTML and native transcripts remain temporary and private. The following excerpts come from rendered copies, with defect reasons and file digests. Where a candidate displayed usage for a failed or incomplete underlying trial, those numbers are omitted here. The literal scores did not change and no candidate reran. The initial author read marked Pages 08 and 09 as full passes. On review, both failed criterion M under the existing closed-drawer readback rule; the scorecard above uses the corrected author ratings. The initial review also failed the catalog prior reports on method for putting grading after the ledger. The rubric requires discoverability without opening details, not a fixed section order. On review both prior catalog reports passed method, but still failed fidelity.

### Page-01

- museum-labels, prior, repeat 1. Literal failures: none. Review defects: M,D. Rules and exact prompts are in the input/settings section after results; no case-specific pass explanation.
- HTML SHA-256: `c32aeb70b4a1b9c27a65403cecdabf96b760b744d7b382a24ffed80f589d9e0f`.

> Read the index card and public label without instruction-condition or candidate model labels. Effort requested: high. Effective setting recorded by the judge session: openai-codex/gpt-6.1-terra, xhigh. Judge limits were not supplied.

### Page-02

- seed-catalog, prior, repeat 1. Literal failures: private_usage. Review defects: F. Both pass rules and effective judge settings are reachable from the visible Checks and calibration link with no disclosure required; the report publishes failure and incomplete counts in a drawer.
- HTML SHA-256: `960fcbc57d2c0bb4b42994f8a98bf0e119b271a142ab1ea12b0e202c13e03e11`.

> Explanation (model): The judge sees the final reply and short reference C09 is skipped because the lot is retired, with exact IDs and no wording or candidate labels. Met requires a link between C09 and its retired status with no claim of submission. Missing means the ID or reason is absent; contradicted means a wrong reason or a claim of submission; uncertain means too ambiguous to decide. All three are scored non-passes. Broken JSON, the judge’s score format, yields no explanation score and leaves the code result intact.

### Page-03

- museum-labels, empty, repeat 1. Literal failures: none. Review defects: M,D. Names the grading checks after results without explaining them against each card; exact wording follows ledger.
- HTML SHA-256: `9704a173ca1d21669f2ccb238539edb7f5b644051995fad41170aaec0ab8594a`.

> Judge: Read the card and public label without treatment or candidate model identifiers. Requested effort was high; the study records openai-codex/gpt-6.1-terra at xhigh effective effort.

### Page-04

- museum-labels, without, repeat 1. Literal failures: none. Review defects: M,D. Gives one generic rubric after the results and does not connect it to each case; wording is also late.
- HTML SHA-256: `9f935e2aa263a3beaae39e497b7f34e717cf5f63c1037c1ffc53a5c45fc85765`.

> The judge saw the index card and label without knowing which instruction or drafting model produced the label. To pass, a label had to meet both rules:

### Page-05

- museum-labels, prior, repeat 2. Literal failures: none. Review defects: M,D. Groups the judge instructions in a shared settings section after results; no visible per-case pass explanation.
- HTML SHA-256: `2c5c717cddb341e26a4a6255e5bf21cd865f79471c22a65f727170cdbd105f39`.

> openai-codex/gpt-6.1-terra; high effort requested, xhigh recorded as effective. The judge saw the index card and public label without condition or candidate model names. Judge limits are not reported.

### Page-06

- museum-labels, empty, repeat 2. Literal failures: tested_guidance. Review defects: M,D,F. Does not show both exact instructions; only global grading after results.
- HTML SHA-256: `0bc2cb78d8762a0da058401b3a02f4a588a0411e1a69f607d4b2f8aad5ec1e28`.

> Two objects, two conditions, one draw per cell. The shared request was “Write one public label for the object on this index card.” The prior instruction asked when the object entered the collection; the revision asked how. Other candidate context was unchanged.

### Page-07

- seed-catalog, revised, repeat 2. Literal failures: none. Review defects: —. Pair of checks, decision and regrade are accurate; shows only successes and compares repeat 3.
- HTML SHA-256: `c9e2d88edd94a214756c24c6985fcac9024fb98cb64888a9e43f9e345a1c5fe5`.

> Usage: Tokens are the units the model counts for input and output. Candidate input counts include cached input. Counts for failed and incomplete outcomes stay in the private audit record. Only repeat 3 passed in both conditions. In that pair, the revised run used 346 fewer input tokens and 36 fewer output tokens. One pair does not establish a general usage change. Judge usage was not measured.

### Page-08

- museum-labels, revised, repeat 2. Literal failures: none. Review defects: M. Pairs the rules with both cards, but the effective judge model and effort were only in a closed disclosure.
- HTML SHA-256: `1603379d6c666f4c6e0f2ad93eba253b1fec2cc12cebdbb0187bc23ee4bb4839`.

> The judge checked card M-BELL against each label. A pass needed to identify the gift and either leave out 1931 or show it was unconfirmed. The check could not verify the ledger itself or tell whether visitors would understand the label.

### Page-09

- seed-catalog, revised, repeat 1. Literal failures: none. Review defects: M. The report preserved the scores and success-only usage, but effective judge model and effort were only in a closed disclosure.
- HTML SHA-256: `80954fb23b98f8ade7ece91b458ea897055fb48b877dd2116dbc831dd24ebe5d`.

> Regrade: SC-R1’s saved reply was reused. The recorded receipt says the byte fingerprints matched; the raw fingerprint is not available here for an independent check. Neither the candidate nor the recorder was rerun. Both the judge prompt and effort changed, so the study does not isolate their effects.

### Page-10

- museum-labels, without, repeat 2. Literal failures: none. Review defects: M,D. General rubric and wording appear after the results; does not explain both case-specific rules before the ledger.
- HTML SHA-256: `f16f02f21c8c7993d7b44fd7f3b72a5635189de76dd77fdb42a5e477dc49ab1e`.

> The judge saw the index card and public label, but not which instruction or drafting model produced the label. Only a rating of “met” passed a check. An “uncertain” rating counted as a usable judgment but did not pass; missing or malformed judgments would make the study incomplete.

### Page-11

- seed-catalog, without, repeat 2. Literal failures: private_usage. Review defects: M,F. Code/model rules appear after results; usage includes failed/incomplete rows and treats totals as comparable.
- HTML SHA-256: `647eb7cfa4a53c9bfba5a1e0603268d724c62fd0293bc0e3eed37f1e05190392`.

> The code checks that preview.json has preview set to true, accepts exactly A17 and B23 without duplicates, and skips exactly C09. It does not check the wording or the reason for skipping. In three test examples, the exact record passed, a duplicate B23 failed, and reordered keys passed (3/3 as expected).

### Page-12

- museum-labels, revised, repeat 1. Literal failures: none. Review defects: —. Pairs the judge and passing rules with the two cards; distinguishes uncertainty from an incomplete score.
- HTML SHA-256: `8dd9656d090d89173764e3e8756562c574465644741ca6b1e1fd0ef78cb2b6c6`.

> Brass river bell: The judge compared card M-BELL with the public label. To pass, the label had to communicate that the bell was a gift and either leave out the year or make its uncertainty clear. This does not check whether visitors found the label clear or useful.

### Page-13

- seed-catalog, without, repeat 1. Literal failures: private_usage. Review defects: M,F. Code/model rules appear after results; usage includes failed/incomplete rows.
- HTML SHA-256: `564d6973a94dcaa427fed57636b0478d75533dc3979926f6cbe2a382a03fb8bd`.

> The recorder output must say preview = true, accept exactly A17 and B23 with no duplicates, and skip exactly C09. This checks the record, not the reason for skipping a lot. The check behaved as expected on all three calibration examples: exact record passed, duplicate B23 failed, and reordered keys passed.

### Page-14

- seed-catalog, empty, repeat 2. Literal failures: private_usage. Review defects: M,F. Rules appear after the ledger; includes failure/incomplete usage and a full audit hash.
- HTML SHA-256: `9e08d91a01406aa3b7bb97761c29fcb99ab24ca3fd395a0d85843b15f3d10798`.

> Preview check: The recorder’s preview.json must flag preview, accept exactly A17 and B23 without duplicates, and skip exactly C09. It does not grade wording or reasons. Calibration matched all three expectations: exact and reordered keys pass, duplicate B23 fails.

### Page-15

- seed-catalog, prior, repeat 2. Literal failures: private_usage. Review defects: F. Both pass rules and effective judge settings are visible under Checks and calibration without a disclosure; failed/incomplete usage appears in a drawer.
- HTML SHA-256: `8574e160e3dcc8644da201f7cf5c5f4090a96d53a64498dce64ae8bd87bf8b1f`.

> Read preview.json from the recorder. Pass only if the preview flag is true, accepted keys are exactly A17 and B23 with no duplicates, and skipped keys are exactly C09. Key order does not matter. This does not check the explanation or verify the reason in a skipped row.

### Page-16

- seed-catalog, empty, repeat 1. Literal failures: private_usage. Review defects: M,F. Rules appear after the ledger; publishes failure/incomplete usage and a full audit hash.
- HTML SHA-256: `36f701ec10c932d8e69dfac2ec1a600e26a6b6b5595e1f88dc69ce00202b7fa9`.

> Preview artifact (code): preview.json must have preview set to true, accepted keys exactly A17 and B23 without duplicates, and skipped keys exactly C09. It does not check the reason. Calibration matched all three expectations: exact record and reordered keys pass; duplicate B23 fails.

## Verifier follow-up

The live verifier SHA-256 was `c206ff0036570dc54264fc4d67f1967062133867b81976b11eb0f9bdbe9d59fb`. The checked-in verifier adds rejection of ambiguous duplicate HTML attributes (SHA-256 `d724a0e3c21da77fc75cad3d7e6bf9b8e2f3e342ed53466fd6c8e4f83bf2fd6f`). Its 51 offline calibration vectors passed; a networkless check of all 16 unchanged saved HTML files reproduced every original literal score. These were checks of saved files, not a candidate rerun or a replacement for native audit.

## Run and limits

Native Pi 1.6.1 / Harbor 0.26.0 on shared runner `29c282741ffe12a526d786a699715b845f283105`, `openai-codex/gpt-6.2-sol` medium, 16 turns, 300 seconds for candidate and 60 for verifier. Shared task ends on saving the report and replying; reviewer renders it later. The prior/revised run order was balanced in adjacent one-case blocks. The two controls were run separately. All 12 batches passed offline audit, including actual images and candidate/verifier namespaces; immutable task images matched across conditions. The candidate allowlist enforces the inference hostname, not an API path. No hosted delivery, hosted link verification, production browser checks, or real Git-history lookup was tested.

Historical: v2 had 0 complete/1 incomplete/15 unstarted (browser search consumed the turn budget). v3 had 9 complete/1 interrupted/6 unstarted (outer command timeout). v4 had 1 complete/1 incomplete/14 unstarted (prior wording again triggered browser work and exhausted the turn budget). None of those rows count toward v5.

V5 frozen plan SHA-256 `5fcca3019d21cb890ce99acb64bd372695161b1b7062c16d85272a2e40c31085`; manifest inventory SHA-256 `32fad048d8d735728963441bd7dd917da96bd6bcad52e1f6be98839b5a466295`. The [reproduction instructions](README.md) explain how to draw a fresh sample.
