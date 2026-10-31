# Plain-language guidance study

## Question

Brian understood a practical explanation much more easily than a technical report of the same results. Which short addition to his shared writing guidance best reproduces that clarity without dropping facts or spending unnecessary tokens?

This study tests a standalone writing excerpt, not full deployed agent instructions. The real-world case is paraphrased from the supplied conversation. All other cases are synthetic. No internal service names, credentials, private logs, or conversation identifiers belong in published fixtures.

## Frozen procedure

1. Run four development cases under five conditions: no writing policy, current production paragraph, and three additions. All additions retain every existing safeguard.
2. Read and grade anonymous answers against four separate criteria in `run.mjs`. A fresh-context reviewer sees only the packet, not condition identities or token usage. The parent checks every answer and records disagreements.
3. Select among the three additions. First require accuracy 2 on every development case and no accuracy regression against current guidance. Then maximize the sum of everyday-language, practical-meaning, and term-explanation points. Break ties by lowest sum of input, output, cache-read, and cache-write tokens. A cheaper incomplete answer is never an efficiency gain. Record the decision before confirmation.
4. Run the selected addition, current guidance, and each of three leave-one-component-out ablations on all seven cases. The final three cases are reserved until selection. The repeated development cases are diagnostics, not independent validation. Keep all runs and null or negative results. Do not tune after confirmation.
5. Keep the existing writing safeguards even if a component has no measured effect. If any reserved answer loses required facts or the selected wording loses clarity overall against current guidance, do not promote it. Otherwise recommend the selected addition, with the small-study limit stated.

One response per case and condition per stage. Use the same model and settings throughout. Candidate contexts have no tools, repository files, prior turns, skills, or extensions. The parent runs model calls directly through the existing access-only Pi CLI pattern. This is controlled prompt comparison, not delegated implementation. Three foreground-owned concurrent calls reduce waiting. No background job or schedule is created.

Use the saved role model for separate-context judging. The configured judge and generator use the same model family; do not claim model diversity or human comprehension testing. Plain-language grading is subjective. Brian's preference is the final authority.

## Grader calibration

Before grading generated answers, use the same rubric on these answers to the auth-rotation case:

- Correct: "Both machines used the same login credential. When one renewed it, the other was left with an old value. Sign in separately on the remote host. Keep the working login and never share the credential. Nothing has been changed yet." Expected accuracy 2 and everyday/meaning/terms 2 each.
- Incorrect: "Both hosts are fixed. Revoke both logins and paste the shared token into the remote shell." Expected accuracy 0, irrespective of its readable words.
- Technically accurate but opaque: "OAuth refresh-token rotation superseded the shared credential, yielding invalid_grant at the lagging consumer. Independently authenticate the remote device without revoking the working grant or exposing credentials. No mutation occurred." Expected accuracy 2, everyday 0 or 1, meaning 0 or 1, terms 0.
- Equivalent clear answer: "The second machine is trying to use an old login credential. Give it its own login. The first machine replaced their shared credential when it renewed its login. Leave that working login alone and keep credentials private. These are next steps; no change has been made." Expected accuracy 2 and everyday/meaning/terms 2 each.

Preserve calibration responses. A failed calibration blocks selection; fix the rubric and replay all saved answers without regeneration if needed.

## Run

```sh
node evals/plain-language/run.mjs development tmp/plain-language/dev
node evals/plain-language/run.mjs confirmation tmp/plain-language/check suggested
```

Replace the final argument with the frozen selected variant. Each output directory must be new. A run freezes exact prompts, source hashes, model settings, CLI version, order, and grading rubric. It retains JSON event streams, answers, usage, stop reasons, and infrastructure failures with SHA-256 receipts. Incomplete calls are not model-quality failures or passes. Do not retry a generated answer to improve its score.

Review `packet.json` without reading `labels.json` first. Save scored rows separately, then join labels to scores and usage for the report. Report per-case quality, each ablation, input/output/cache tokens, and combined token totals. These are token counts, not dollars. Shared prompt overhead is present in every condition; only matched differences estimate this change's cost. Answers may be longer even when instructions are shorter.

The maintained fixtures protect clarity and factual completeness across explanation, operational status, credentials, deletion, numerical advice, and unfamiliar terminology. This is an opt-in live study, not a deterministic CI test.
