# pstack trial

The trial adds [poteto's official pstack](https://github.com/cursor/plugins/tree/main/pstack)
without replacing Superpowers or the existing delivery workflow. It is available
in the managed Pi, Claude Code, and Codex setup. Start a fresh session after
provisioning. Reloading skills in a native Pi session also works.

## Start here

| Harness | Example |
| --- | --- |
| Pi | `/skill:pstack how does this project's request cancellation work?` |
| Claude Code | `/pstack how does this project's request cancellation work?` |
| Codex | `$pstack how does this project's request cancellation work?` |

Use `pstack` with a task to enter `poteto-mode`. To select a skill directly,
put its exact upstream directory name first. For example, in Pi:

```text
/skill:pstack why was this retry boundary designed this way?
/skill:pstack benchmark-checklist assess these before/after results
/skill:pstack blast-radius inspect this small change before I ship it
/skill:pstack add pagination to this endpoint
```

The first three select a specific skill. The last uses poteto-mode. With no
arguments, the entry loads poteto-help. This is one local command, not 54 new
slash commands. Direct upstream references are read from the pinned tree.

Start with `how`, `why`, and `benchmark-checklist`. They can help assess whether
pstack adds useful evidence or just repeats the existing workflow. Full
poteto-mode is a broader experiment and can require authorized delegation,
independent review, models, and integrations that a session does not have.

## What is installed

- One explicit-only `pstack` entry in each harness. Pi and Claude use
  `disable-model-invocation: true`; Codex also disables implicit invocation in
  `agents/openai.yaml`.
- The official source at commit
  `101b274dd991f694e1f7024be2157e5f3adf07de`, not a community fork.
- All 54 upstream skills, support files, agent briefs, documentation, README,
  and MIT license, unchanged, at
  `~/.local/share/new-machine-bootstrap/pstack`.
- A local adapter beside the entry. Read it before upstream instructions.

The reference tree is outside skill discovery. This avoids generic-name
collisions (`tdd`, `how`, `why`) and unwanted activation of upstream principles.
The entry is linked by the existing managed-skill linker.

## Limits

This is a portability trial, not full Cursor feature parity. Existing policies
control delegation, repository changes, test value, publication, merge,
provisioning, cleanup, and secrets. Upstream autonomy text grants no additional
authority. The adapter maps current tools rather than inventing Cursor APIs or
assuming its model slugs are available. Required missing capabilities block
the affected workflow; optional omissions must be reported.

This does not install cursor-team-kit, external MCP servers, registered
poteto-agent types, cloud agents, or Cursor automations. `setup-pstack` cannot
configure Pi, Claude Code, or Codex in this trial. Bundled scripts are preserved
for reference, not run at installation. Existing PR workflows remain in charge.

Installation, checksums, and repeat provisioning prove packaging, not workflow
quality or model compliance. Cross-harness live behavior and any improvement in
quality, elapsed time, or token use remain unverified until actual trials.
No existing prompts or safeguards were optimized or removed.

## Apply and maintain

```bash
bin/provision --tags managed-skills
```

The upstream pin is intentionally frozen during the trial. See
`roles/common/files/vendor/pstack/UPSTREAM.md` for source, scope, update review,
and checksum verification. Review behavioral and executable changes before any
new snapshot. Keep upstream bytes intact; local portability policy belongs in
the adapter.

## Feedback and rollback

The owning BB thread registers a one-shot feedback continuation seven days after
local integration. It asks what you used, what helped, what added friction or
cost, and whether to retain, expand, or remove the trial. It does not change the
setup without a new decision. The thread reports the durable automation ID.

For rollback, remove only `pstack/pstack` from the managed entry source tree and
provision managed skills. Synchronization removes the canonical entry; the
linker removes its stale links. The inert reference snapshot can stay until its
removal is separately approved. Other skills and defaults remain unchanged.
