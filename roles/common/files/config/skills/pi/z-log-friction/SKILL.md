---
name: z-log-friction
description: Use when the user directly invokes the friction logging command after a correction, unnecessary approval request, early stop, repeated manual step, or other agent friction.
disable-model-invocation: true
---

# Log Friction

Run this skill only because the user directly invoked `/skill:z-log-friction`. If the request was inferred or automatic, do not log anything; state that direct invocation is required and stop.

1. Select exactly one category:
   - `correction`
   - `unnecessary-approval`
   - `stopped-early`
   - `repeated-manual-step`
   - `other`
2. Write one concise, factual, single-line summary. Use the supplied arguments and current context only to identify the friction. Do not quote the conversation or store exact user text, full prompts, full responses, credentials, tokens, secrets, or sensitive values. Omit sensitive values instead of masking part of them.
3. Run `git rev-parse --show-toplevel` to obtain the repository when available. Otherwise, use the current working directory.
4. Call `pi-friction` exactly once with this option form: `pi-friction log --category "$category" --summary "$summary" --repository "$repository"`. Add `--session-id "$PI_SESSION_ID"` only when `PI_SESSION_ID` is nonempty. Pass each value as a separately quoted argument. Never use `eval` or interpolate data into executable shell syntax.
5. Parse the helper's JSON response. Report only: `Logged <id> on <host> as <category>.`

Do not diagnose causes, propose changes, start a review, or stop the current task unless the user asks.
