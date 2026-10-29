# Native Pi-login repair verification

## Reproduction and repair
Before the repair, selecting `openai-codex/gpt-6.1-sol` failed with:

```text
Error: Supply an explicit openai/model or anthropic/model
```

A disposable native Pi probe established that an API-key-typed stored bearer is not accepted for this subscription provider. The access-only OAuth shape, with an empty refresh placeholder and the original expiry, succeeded. No host refresh credential was transferred.

After the repair, a real Harbor 0.24.0 permission workflow ran with Pi 1.4.0 and `openai-codex/gpt-6.1-sol`. Both API-key variables were explicitly unset. The failed-approach case completed investigation and implementation in one continuing native session. Both steps passed task and authority checks, with ten tool calls per step and no infrastructure errors.

```text
permission-guidance: 1 case(s), 1 condition(s), 1 trial(s), 2 planned user turns (not a billed-request count)
Running current/failed-approach, trial 1/1
Current policy: PASS
```

The report records 27,461 input, 3,319 output, 134,784 cache-read, and zero cache-write tokens. These are transport-smoke measurements, not evidence of guidance token savings. The grader confirmed native settlement, tool/result evidence, protected snapshots, and session continuity. A scan of 160 retained files found no JWT-like material and no temporary credential files. The disposable workflow container was removed. This does not prove credential isolation against hostile candidate tools.

## Offline and independent checks
Four credential lifecycle checks pass. They execute the production wrapper with synthetic export/upload boundaries and cover private access-only transfer, partial-upload/native-failure cleanup, malformed/expired credentials, and refusal to overwrite existing container credentials. Four Node permission checks and ten Python permission verifier checks pass.

The shared 17-test Harbor suite retains its independently reproduced pre-existing naming-loader failure and two related errors. It reports `Production set_session_name was not registered`. The auth repair does not change the naming suite or its loader. These failures are not reported as passes.

Two independent design contexts compared container-native access-only auth with a host controller/inference broker. Both used the same configured model. A fresh-context implementation review found no correctness or security findings for the documented cooperative-fixture scope. Its redundant module-summary docstring finding was accepted and removed. The clean-tree whole-branch review then found that non-object JSON configuration could raise AttributeError in the existing timeout grader. Reproduced that failure with null, array, numeric, Boolean, and string artifacts; the grader now records task=false instead of aborting the remaining comparison as infrastructure failure.

## Evidence limits
Local evidence is under `tmp/pi-login-native-smoke-2/` and `tmp/concise-permission-ablation/`. A first fresh staging attempt failed because provisioning had removed the formerly installed fixed skill path. The exact skill was recovered from the already-frozen task and checked against its recorded SHA-256 before the successful run. The failed attempt remains separate and made no model calls.

No deployed guidance, manual credential changes, Docker restart/reset, merge settings, or persistent automation changes are part of this repair. The [matched guidance comparison](2026-10-29-concise-permission-comparison.md) was subsequently refrozen with the OAuth provider and completed separately. Authentication smoke results do not select a prompt winner or justify removing safeguards.
