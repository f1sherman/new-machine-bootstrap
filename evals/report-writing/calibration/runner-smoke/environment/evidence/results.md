# Native runner verification

On November 20, one native Pi candidate opened a local fixture PR. The runner audited the execution and the images that ran. The original verifier accepted the submission but missed valid wording in its body. The corrected verifier passed the same receipt. This supports using the runner for cooperative local workflows, not production PR acceptance or a guidance comparison.

## Local PR workflow

**User task:** “Please open a PR for the changes on this branch.”

The fixture diff changes a delivery retry delay from 5 to 30 seconds. Pi ran in Harbor, read the fixture skill, inspected the Git diff, pushed the branch to a local bare repository, and submitted a title and body. Git, Pi, inference and the separate verifier were real. The fixture skill and local submission tool stood in for production PR guidance, review, publication and monitoring. The verifier read the tool's receipt, not Pi's final answer.

The [offline calibration](tasks/open-pr/tests/calibrate.py) ran the actual verifier before inference on the first three cases. It also passed those cases with the corrected verifier. Scores are in the order **submitted / descriptive title / describes change**.

| Case | What happened | Original | Corrected |
| --- | --- | --- | --- |
| PR-C1 | Plausible draft with the correct delay change; no submission reached the tool. | 0 / 0 / 0 | 0 / 0 / 0 |
| PR-C2 | Local tool accepted “Increase retry delay” and a body saying 30 seconds instead of 5 seconds. | 1 / 1 / 1 | 1 / 1 / 1 |
| PR-C3 | Local tool accepted “Wait longer between retries” and equivalent wording using “five seconds.” | 1 / 1 / 1 | 1 / 1 / 1 |
| PR-S1 | Setup stopped before OAuth export or native launch. The baked skill directory had the wrong owner. | Incomplete | Not regraded |
| PR-L1 | One live `current` trial. The tool accepted the intended branch, a descriptive title, and the correct change. The original verifier did not recognize “from 5 to 30 seconds”; the corrected verifier does. | 1 / 1 / 0 | 1 / 1 / 1 |

Harbor regraded PR-L1 with the corrected verifier. The accepted receipt matched byte for byte. No replacement draw or semantic judge ran.

## Accepted submission

Base `main`, head `longer-retry-delay`, commit `c7f02aad55eb16faaba38f9e1b3ad90484d3b672`. Local receipt URL: `https://pr.example.invalid/1`.

Title: **Increase delivery retry delay to 30 seconds**

```markdown
## Summary
Increase the delivery retry delay in `delivery.toml` from 5 to 30 seconds. This gives transient failures more time to clear before the next attempt.

## Validation
`git diff --check origin/main...HEAD` passed. No runtime tests were run.
```

## Audit evidence

Harbor `0.26.0`, Pi `1.5.2`, one candidate at `openai-codex/gpt-6.2-sol`, `medium`, 12 turns maximum and a 900-second cap. The native session recorded that model and effort. The identity and egress preflight passed before the OAuth export, which required at least 1,200 seconds of remaining access-token life. This did not test a run that consumed the full time budget.

The original run passed offline audit. Docker inspection recorded distinct candidate, verifier and sidecar containers. Each role shared only its own sidecar's network namespace. The candidate ran with the inference allowlist; the verifier and the regrade used the no-network policy. The verifier used the same pinned task image in a fresh container, without the candidate credential.

| Evidence | SHA-256 |
| --- | --- |
| Built runtime image | `a628988af3baf5d5bc605cbc88b98c2837580e98dde023aebe166719f9cef34e` |
| Actual candidate, verifier and regrade task images | `78210e96e60e53845c3c5c0984ef7659b01b2132d7ff6d3eb2e6fe331195d400` |
| Actual enforcement image for each role | `8f51411c76ed0be125ecaaf6ddf7341ae755246e527f64650da3431be5a89bf4` |
| Frozen manifest | `4c55ed24ea5fb3032818581aa371de4bc2dc5bd2c0a8c7297bdaec6f347db46f` |
| Original run receipts | `8fd4142d794cd7d51aba423ec5829931533b995c3b417695f63d63c8a810f648` |
| Accepted submission receipt | `3f6b6862357f2617e04a83a72cfb7b36f7a52a00bef2b04a48d06ecb006a6d9f` |
| Original verifier source | `43d863eb7cfa785075f6bd7623440fbbf81d65cfa06bb6d26a431d68226e3b8f` |
| Corrected verifier source | `286101e1ba1a56e5671065fb68961496ecbe86660c712d3233803307e265a1d4` |
| Regrade live-container image proof | `7fab3fd992d4b2253a0490f8b99ef3ca192653098bf1a1053cc4613d3dc61c76` |

## Earlier component diagnostics

### Final answer at the turn limit (November 18)

**User task:** `Reply with READY.` Global instruction: `Answer user requests directly.` Both trials used the original Terra settings: `openai-codex/gpt-6.1-terra` at `medium`, Harbor `0.26.0`, Pi `1.5.2`, `current` only, one allowed model turn, and 900-second agent and 60-second verifier caps. Native Pi made real inference requests and used no tools. A separate mechanical verifier emitted a completion marker. It did not grade the answer's meaning.

| Case | Limiter | Final text / stop reason | Native settled state | Collection |
| --- | --- | --- | --- | --- |
| TURN-B | Original Harbor limiter | `READY.` / `stop` | Aborted | Incomplete: no terminal response admitted |
| TURN-A | Corrected adapter | `READY.` / `stop` | Not aborted | Complete; marker reward 1; offline audit passed |

Each trial used 1,152 input and 6 output tokens. The corrected adapter refuses a turn beyond the budget at turn start instead of aborting a completed final answer. Separate inert callback checks at limits 1, 2 and 80 confirmed that the first excess start aborted. These are lifecycle checks, not workflow trials. The live pair predates the new image audit and OAuth lifetime gate.

### Offline checks for the current runner

| Case | What ran | Evidence that matters |
| --- | --- | --- |
| SKILL-1 | Native Pi loader and startup checks with fixture credentials and inert transport | Body-only removal kept discovery; removing frontmatter did not. Hidden or missing skills and a selected skill in the empty control triggered refusal. Removing the required startup advertisement or budget refused the request; a free-standing skill example did not replace the native list. |
| STAGE-1 | Current-only staging and networkless calibration | A standalone skill reached calibration without having to construct an unused ablation. |
| SCHEMA-1 | Before/after judgment verifier in a networkless container with synthetic inputs | The verifier used the frozen document and rubric, removing stale-copy false accepts and rejects. Blank excerpts no longer satisfy `met` or `contradicted`; exact excerpts and empty lists for `missing` or `uncertain` remain valid. |
| AUTH-1 | Production credential helper with a fake host process and fixed clock | At a 1,200-second minimum, 1,201 seconds remaining passed and 1,199 failed. The legacy 300-second minimum still accepted 301 seconds remaining. |

No model ran for these offline checks. The [runner tests](../runner/test_runner.py) and [smoke fixtures](README.md) remain runnable.

## Limits

- The smoke used a synthetic skill and a cooperative local recorder. It did not test GitHub acceptance, a guidance ablation or the full OAuth trial duration.
- Skill visibility is checked as text. A complete quoted skill list can still fool the check. Skill-targeted runs with prompt-rewriting hooks or ambiguous wrappers are outside the verified scope.
- The runner does not enforce effort by role. A valid judgment schema does not establish judgment quality.
- Setup recovery is disabled. Historical runs do not gain the new image proof. Raw traces and provider reasoning stay out of this report.
