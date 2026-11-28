# Grade the rendered report

The reviewer sees only an opaque ID, the case name and rendered HTML. Withhold
reporting treatment, candidate settings, logs and verifier scores until the
readback is recorded. The models/settings of the *underlying* study are evidence,
not treatment labels for this assessment. Shuffle all eligible reports together.
Do not rewrite their contents to blind them. Style, detail and any volunteered
mentions may still suggest a treatment; record accidental unblinding.

1. **Readback:** in the first minute, start at the top, without opening
   evidence drawers or following links. Write down the question, disposition,
   strongest observation and decision-critical limit. Find the exact prompt for
   each case and state what behavior it tests. Separately say what comparison
   would change the decision and whether it occurred. For every scored check,
   identify who or what graded it, which artifact they read, and the concrete
   rule for a pass. If there is a judge, record effective model/effort, not the
   requested setting or candidate setting. Record `not found` rather than
   guessing. Do not consult the source while answering.
2. **Delivery:** open only verifier-admitted pages in a fresh browser profile
   with network and page script execution disabled before navigation; don't
   follow embedded links. At 390 and 1050 CSS pixels require readable headings,
   named sections, critical information not encoded by color alone, legible
   text without clipping, and navigable evidence by keyboard. Verify visible
   focus and Space/Enter on each disclosure if used. Tables or preformatted
   excerpts may scroll inside an accessible region; the whole page shouldn't
   scroll sideways. No particular design, CSS, or optional disclosure required.
   This is not full WCAG or screen-reader conformance.
3. **Source review:** after saving the readback, open the case records. Score
   the criteria below (Pass/Fail/Not scored); write the observed answer and
   a brief reason with its location. Inspect all case and repeat rows, not
   just the most favorable pair. `Not scored` means the assessment itself was
   unavailable, not that a report omitted a required fact. Absence in a
   delivered readable report is a Fail. A complete native trial that never
   wrote HTML fails delivery; other checks cannot be satisfied. An incomplete
   native trial remains unscored. Do not use invisible text or source comments
   as evidence. No credit for saying a rubric exists, or for a link alone.

## Rating criteria

| Check | Pass rule |
| --- | --- |
| Method and rule | Readback maps each method and named artifact to its case, explains what could look correct yet fail, and gives the operative pass conditions and reducer. Report distinguishes effective judge and candidate settings, includes calibration and describes a material grading blind spot. Equivalent language earns credit. |
| Decision and limit | Correct supported disposition, one strongest matched result (or single smoke capability), and one decision-critical limit recovered in the readback. State the decision threshold and whether it was met, not merely task pass rates. Exact wording under test is visible near the beginning, and exact user prompts are easy to find from the top or results. |
| Ledger | Each recorded row maps to the right case/condition/repeat. Graded failure, uncertainty and invalid or incomplete measurement agree with records; no pooling or replacement. Regrade preserves original and corrected scores, how they differ, which artifact was unchanged, and whether any candidate ran again. |
| Fidelity | Source comparisons agree, actual reviewed task inputs and outputs are available in the report and tied to the right cases; coverage, artifact provenance, grading limits and unavailable evidence are accurately stated. No invented prompts, traces, results, or release claims. |
| Delivery | Pass step 2 and all delivery-related Harbor checks. |

### Case keys (source review only)

- **Museum labels:** label and card; both acquisition and certainty must be
  `met`. First asks for the documented transfer type, not a date; second
  allows omission or explicit uncertainty about an unconfirmed date. Match
  four rows to both cards. Clock revised is `uncertain` for acquisition, not
  missing or invalid. Bell improves from both criteria failing to both met.
  Limited adoption is supported by the stated rule, not proof for visitors
  or conflicting cards. Effective Terra `xhigh`, not requested `high` or
  candidate Sol `medium`. Two clean calibrations, no evidence under conflict.
- **Seed catalog:** code grades the recorder JSON for preview flag, exact
  accepted keys A17 and B23 with no duplicate, and exactly C09 skipped;
  model grades the final reply against ID, retired reason and no claim of
  submitting. Both required. J1 and J2 differ in effective effort and synonym
  handling; retain J1 failure to recognize the synonym and J2 acceptance on
  the same reply bytes, not a second candidate. Source reports agreement of
  digests but does not include a digest. SC-R2 incomplete model JSON, code
  Pass; SC-P1 is the behavioral preview failure. No promotion. Local recorder
  is a stand-in. Retain all three repeats and report calibration and scope
  limits. Only SC-R1, SC-P3 and SC-R3 get per-trial totals (input/output:
  4379/601, 4513/673, 4167/637). Only repeat 3 supports matched usage; input
  includes cache. Keep full hashes in the named audit source, not the brief.
  Explain CAT-14's one clean local preview, the adapted retired-lot case and
  the untested live boundary. No published URL is supplied.
- **#793 calibration only:** reproducible local PR, no fragment or live PR
  claim. Deterministic receipt checks, no model judge: exactly one receipt
  matching base/head/commit/fixture URL, title regex accepts retry or retries,
  body requires evidence of 5 and 30 seconds by pattern. Body alone flips
  `0→1`; same receipt, no candidate rerun. Match calibration to the known
  correct, wrong, equivalent cases, and PR-S1 to setup incomplete. Report
  limitations of pattern matching and scope of the stubbed workflow.

## Calibrate before inference

Run networkless Harbor calibration for the literal checks. Use the #793
reference and an equivalent restyle, plus plausible faults that leave the
literal verifier unchanged: missing body rule, a purported Pi rerun, setup
incomplete called a scored failure, or a hidden core section. Each expected
semantic failure must be caught in the indicated criterion. Test both valid
variants with the same checklist. Preserve the answers and expected/observed
scores. The author’s browser self-audit is a pilot, not a blinded human result.
The operator approved the blinded AI source review plus offline Chrome
checks instead of a human. The model distinguished all six constructions.
No blinded human readability measurement occurred. The author applies the
rubric to rendered reports under opaque IDs before pairing scores to
conditions. No paired model-judge calls are part of the matrix.
