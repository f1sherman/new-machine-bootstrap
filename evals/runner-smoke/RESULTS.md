# PR workflow smoke result — 2026-11-20

One native Pi candidate completed the synthetic [PR workflow](README.md). It read the fixture skill, inspected the real Git diff, pushed to the local bare repository, and used the local submission tool. The separate verifier graded the tool's accepted receipt, not the final answer.

| Observation | Original checks: submitted / title / change | Corrected checks |
| --- | --- | --- |
| Draft only, no submission (offline calibration) | 0 / 0 / 0 | 0 / 0 / 0 |
| Valid submission and equivalent wording (offline calibration) | 1 / 1 / 1 each | 1 / 1 / 1 each |
| Single live candidate, `current` | 1 / 1 / 0 | 1 / 1 / 1 |

The original verifier missed the valid shared-unit wording “from 5 to 30 seconds.” The corrected verifier accepted it in Harbor's verifier-only regrade. The accepted receipt matched byte for byte. No replacement candidate or semantic judge ran. A separate setup attempt stopped before OAuth export or native launch because the baked skill directory had the wrong owner. Its incomplete evidence remains separate.

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

Raw data stays under ignored `tmp/` during review. The run used a synthetic skill, a local origin, and a cooperative receipt recorder. It does not establish production PR acceptance, general skill visibility, semantic judge quality, or behavior in a fragment comparison.
