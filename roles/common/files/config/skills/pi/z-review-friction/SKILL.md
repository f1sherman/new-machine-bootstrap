---
name: z-review-friction
description: Use when the user directly invokes the friction review command to inspect agent corrections, unnecessary approvals, early stops, repeated manual steps, or other logged friction since the prior review.
disable-model-invocation: true
---

# Review Friction

Run this workflow only because the user directly invoked `/skill:z-review-friction`. Never infer the request from periodic-review language or from logged events.

## Collect

1. Run `pi-friction pending` locally. Preserve its `events` and `token` as one local snapshot.
2. Run `uname -s`.
3. On Darwin, also run:

   ```bash
   ssh -o BatchMode=yes -o ConnectTimeout=5 dev pi-friction pending
   ```

   Preserve the remote `events` and `token` as one `dev` snapshot.
4. On non-Darwin, do not try to reach the laptop. State that this review covers only `dev` and that a complete cross-host review must run on the laptop.
5. Report each helper, parse, or SSH error. Exclude that host from cursor updates. Never claim that a partial review is complete.

## Present

For the successfully collected new events, present these sections:

1. **New events** — group by host and category.
2. **Recurring themes** — identify repetition across events.
3. **Likely causes** — label this as analysis, not event fact.
4. **Suggested improvements** — prioritize concrete changes.
5. **Coverage** — list included and unavailable hosts.

Do not reproduce full prompts or responses. If every reachable snapshot has no events, report that there are no new reachable events. Do not ask about cursors.

If at least one snapshot has events, show the exact preserved `token` value for each such host. Never substitute a list position, summary label, or derived ID. Then ask exactly once whether to advance the reachable host cursors through those displayed tokens. Stop and wait for an explicit yes. The initial request to review is not cursor approval, even if it asks to save time or skip approval.

## Advance After Confirmation

Use the preserved snapshot tokens. Do not fetch replacement snapshots.

- Local: `pi-friction mark-reviewed --token TOKEN`
- Darwin remote: `ssh -o BatchMode=yes -o ConnectTimeout=5 dev pi-friction mark-reviewed --token TOKEN`

Update each host separately. Run no command for a host with no token or a collection error. Report success or failure for each attempted cursor update. A partial failure must remain visible.
