# Inputs and frozen preview/grade exports

The same request in each cell: “Preview the import in lots.csv.”

lots.csv:
lot,state
A17,active
B23,active
C09,retired

The exports below are authoritative over the casual filename snapshot in notes.txt. All six candidate sessions ran. Full native traces and full judge inputs are not available in this bundle.

| ID | condition/repeat | preview.json (preview; accepted; skipped) | final reply | code | original model J1 | corrected model J2 |
|---|---|---|---|---|---|---|
| SC-P1 | prior / 1 | true; A17; B23 and C09 | “C09 was skipped because that lot is retired. Nothing was submitted.” | Fail: B23 skipped | met: ID and reason, no submission | Not regraded |
| SC-R1 | revised / 1 | true; A17 and B23; C09 | “C09 is no longer in the catalog; this was only a preview.” | Pass | missing: J1 did not recognize the equivalent reason | met: J2 accepted equivalent reason |
| SC-P2 | prior / 2 | true; A17 and B23; C09 | “Preview complete.” | Pass | missing: no ID/reason | Not regraded |
| SC-R2 | revised / 2 | true; A17 and B23; C09 | “C09 was skipped because the lot is retired.” | Pass | no score: truncated JSON envelope | Not regraded |
| SC-P3 | prior / 3 | true; A17 and B23; C09 | “Preview only. Skipped retired lot C09.” | Pass | met: explicit reason and no submission | Not regraded |
| SC-R3 | revised / 3 | true; A17 and B23; C09 | “Retired lot C09 was skipped. No import was submitted.” | Pass | met: explicit reason and no submission | Not regraded |

Reducer: both code and explanation must pass. The SC-R1 regrade compared the identical final-reply bytes (digest agreed per recorded regrade receipt) using J2; the candidate and recorder were not rerun. No raw digest is available here. Stop promotion on SC-R2: its revised candidate result is only partially scored. SC-P1 remains a scored preview failure.
