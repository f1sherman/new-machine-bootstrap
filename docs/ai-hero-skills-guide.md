# AI Hero skills evaluation and usage guide

This guide records the evaluation of Matt Pocock's AI Hero skills for Brian's
agent workflow. It is both a decision ledger and, for selected skills, a usage
guide.

The primary selection criterion is whether a skill improves outcomes without
requiring unnecessary active time from Brian. Existing automated workflows are
preferred when they provide the same or better behavior.

Evaluated source:

- Guide: <https://www.aihero.dev/skills>
- Repository: <https://github.com/mattpocock/skills>
- Tag: `v1.2.3`
- Annotated tag object: `835450ef244ab7335f75d95b83e7d979eae22a6d`
- Peeled source commit: `6acc160e4e0cd062dbbbd7a1b26ae92855edf07e`

## Decision states

- **Install**: Manage the skill in this repository and document when to use it.
- **Skip**: Do not install it.

## Decisions

| Skill | Decision | Summary |
| --- | --- | --- |
| `setup-matt-pocock-skills` | Skip | No selected skill needs its issue-tracker configuration. Avoid adding per-repository setup and tracker maintenance. |
| `ask-matt` | Skip | It adds a manual routing step, knows only Matt's skills, and duplicates automatic skill selection. |
| `grill-with-docs` | Install, adapted, user-only | Use only when Brian explicitly requests a deep design interview for large, ambiguous repository work. The local portability patch loads `grilling` and `domain-modeling` through the harness skill mechanism, or reads their sibling `SKILL.md` files when the mechanism is unavailable or cannot load either dependency, including invocation-policy rejection. Prevent model invocation. |
| `to-spec` | Skip | Existing workflows already create versioned specifications and plans without a separate issue-tracker artifact or manual invocation. |
| `to-tickets` | Skip | Existing planning and subagent orchestration avoid manual tracker, dispatch, and completion work. |
| `implement` | Skip | Existing `z-fix` and `z-quick-pr` workflows add worktree isolation, verification, review fixes, and pull-request creation. |
| `code-review` | Skip | Existing `z-review` resolves the base, reviews a clean tree, fixes worthwhile findings, and repeats to a practical stopping point. |
| `wayfinder` | Skip | Its issue-based, multi-session decision map requires substantial human and tracker work, depends on skipped workflow stages, and still stops before delivery. |
| `prototype` | Skip | Existing brainstorming and spike workflows can answer narrow design questions without fixed HTML formats, permanent prototype branches, or accidental automatic invocation. |
| `research` | Skip | Existing research tools and controlled subagents provide the same value without recursive delegation risk or mandatory stale repository artifacts. |
| `improve-codebase-architecture` | Skip | It tends to generate speculative maintenance work and long interviews; focused architecture review can use existing audit tools when a planned change justifies it. |
| `diagnosing-bugs` | Skip | It strongly overlaps with `systematic-debugging` and over-triggers, but several of its stricter diagnosis rules should strengthen the existing harness. |
| `resolving-merge-conflicts` | Install, adapted | Use when Git is already stopped on merge or rebase conflicts. Preserve intent from both sides and run repository checks. Adapt the absolute `never --abort` rule so an unclear or incorrect operation stops for a real human decision. |
| `triage` | Skip | It is valuable for a large inbound issue queue, but current work is mainly self-initiated and the label state machine adds setup and approval overhead. |
| `wizard` | Skip | Existing direct automation, browser tools, and secret-management guidance are preferable; generate a dedicated script only when a repeatable manual procedure justifies normal feature work. |
| `grill-me` | Skip | Its large stateless interview adds substantial active time and duplicates the existing task-scaled brainstorming workflow. |
| `handoff` | Skip | Existing create/resume handoff skills are more durable and verify stale state. Add explicit redaction and reference-without-duplication guidance to the current handoff workflow. |
| `to-questionnaire` | Skip | There is no current recurring case where work is blocked on knowledge held by another person. A questionnaire can be drafted ad hoc if that changes. |
| `teach` | Skip | There is no current multi-session learning project to justify a dedicated course workspace and its maintenance overhead. |
| `wait-what` | Install, user-only | Use on demand when an agent response does not land. Upstream metadata makes it user-only. It restores missing context, uses ASD-STE100 Simplified Technical English, and returns to established project terminology. |
| `writing-for-agents` | Install | Use when creating or editing skills, agent instructions, prompts, plans, tickets, or other agent-facing documents. It complements skill testing with context-load, pointer, completion-criterion, and pruning guidance. |
| `codebase-design` | Skip | Useful depth and locality principles are retained, but mandatory vocabulary and automatic activation can trigger unbounded redesign that duplicates current design guidance. |
| `domain-modeling` | Install, user-only | Install unchanged except for `disable-model-invocation: true`, as a dependency of `grill-with-docs`. |
| `grilling` | Install, user-only | Install unchanged except for `disable-model-invocation: true`, as the interview engine for explicit `grill-with-docs` sessions. |
| `tdd` | Skip | It duplicates the existing TDD skill, requires human seam confirmation, depends on skipped `codebase-design`, and lacks the repository's material-value test gates. |

## Installed-skills quick reference

All six skills keep their upstream names in every harness. To invoke a skill
explicitly, use its exact name with the harness-specific form shown below:

- Claude Code: `/grill-with-docs`
- Codex: `$grill-with-docs`
- Pi: `/skill:grill-with-docs`

Substitute any other installed name for `grill-with-docs`; for example,
`/wait-what`, `$wait-what`, and `/skill:wait-what` invoke `wait-what`.

The deep-design bundle (`grill-with-docs`, `grilling`, and `domain-modeling`) is
user-only. Each skill has `disable-model-invocation: true`, and its Codex
metadata has `policy.allow_implicit_invocation: false`. `wait-what` is also
user-only, as specified by its upstream `disable-model-invocation: true`
metadata. `resolving-merge-conflicts` and `writing-for-agents` do not disable
model invocation, so an agent can select them when their described conditions
match. A user can still invoke either one explicitly.

| Skill | Exact explicit trigger | Invocation policy and when to use it | Do not use it when |
| --- | --- | --- | --- |
| **grill-with-docs** | Claude `/grill-with-docs`; Codex `$grill-with-docs`; Pi `/skill:grill-with-docs` | User-only. Start a deep design interview for large, ambiguous repository work that should produce or refine domain context and architecture decisions. It loads both `grilling` and `domain-modeling`. | The task is small or already well specified, ordinary planning is sufficient, or the user has not explicitly requested the deep interview. |
| **grilling** | Claude `/grilling`; Codex `$grilling`; Pi `/skill:grilling` | User-only. Stress-test a plan, decision, or idea through a relentless decision-tree interview without requiring the documentation bundle. | The need is fact-finding the agent can perform, a routine clarification, or implementation rather than an explicit interview. |
| **domain-modeling** | Claude `/domain-modeling`; Codex `$domain-modeling`; Pi `/skill:domain-modeling` | User-only. Build or change domain terminology, a ubiquitous language, context documents, or architectural decision records. It is also loaded by `grill-with-docs`. | Merely reading established terminology, or work that does not change the domain model or record a decision. |
| **wait-what** | Claude `/wait-what`; Codex `$wait-what`; Pi `/skill:wait-what` | User-only. Invoke after an agent response does not land and needs to be re-pitched with enough context, ASD-STE100 Simplified Technical English, and established project terminology. | The prior response is already clear, or the request is for new analysis rather than a clearer restatement. |
| **resolving-merge-conflicts** | Claude `/resolving-merge-conflicts`; Codex `$resolving-merge-conflicts`; Pi `/skill:resolving-merge-conflicts` | Model-invokable when Git is already stopped on an in-progress merge or rebase conflict. Establish both sides' intent, resolve without inventing behavior, run repository checks, and finish the clearly intended operation. | There is no active merge or rebase conflict, or available context cannot establish that the operation should continue; in the latter case, stop for a human decision. |
| **writing-for-agents** | Claude `/writing-for-agents`; Codex `$writing-for-agents`; Pi `/skill:writing-for-agents` | Model-invokable when creating or editing skills, agent instructions, prompts, plans, tickets, or other agent-facing documents. Use its context-load, pointer, completion-criterion, and pruning guidance. | The audience is only human, the task is implementation rather than agent-facing writing, or a document-specific rule is more authoritative. |

## Maintenance and upstream updates

### Managed source and commands

The upstream tag is pinned at
`tool_versions.git_tags.mattpocock_skills` in `vars/tool_versions.yml`. Read the
current tag, annotated tag object, and peeled source commit from that pin and
the generated `UPSTREAM.md` files. Do not describe the annotated tag object as
the source commit.

`roles/common/files/vendor/mattpocock-skills/` is a complete generated tree for
the six selected skills. Do not hand-edit it. After deliberately changing the
pin, regenerate it from the repository root:

```sh
bin/update-ai-hero-skills
```

Verify that the checked-in tree is reproducible from the pin with:

```sh
bin/update-ai-hero-skills --check
```

The updater fetches the pinned tag, peels it to a commit, validates selected
source and metadata, requires a regular non-symlink upstream `LICENSE`,
rejects source symlinks, copies only the selected complete skill
directories, applies the local policy patches, writes provenance and checksums,
and replaces the generated tree so removed upstream files cannot linger. It
also rejects a previously recorded tag that has moved to another commit unless
a maintainer explicitly supplies `--allow-moved-tag`.

### Renovate behavior

Renovate watches the `mattpocock/skills` GitHub tags through the pin annotation.
The repository-wide seven-day minimum release age applies. For this dependency,
Renovate adds the `ai-hero-skills` label, uses `AI Hero skills` as the commit
topic, and runs exactly `bin/update-ai-hero-skills` after updating the pin. The
allowed generated changes are bounded to `vars/tool_versions.yml` and
`roles/common/files/vendor/mattpocock-skills/**`; the workflow allowlist permits
only that exact updater command. The scheduled workflow checks daily and can
also be dispatched manually. A Renovate pull request therefore contains both
the pin change and the generated behavior diff for review.

### Local patch policy and review cost

Local adaptations belong in `bin/update-ai-hero-skills`, not in hand edits to
the generated files. There are three policy adaptations:

1. The entire deep-design bundle is made user-only in both skill frontmatter
   and Codex metadata.
2. The `grill-with-docs` portability patch replaces an upstream Claude-specific
   nested invocation. The generated wrapper first uses a harness skill
   mechanism when available. If it is unavailable or cannot load either
   dependency (including invocation-policy rejection for these user-only
   skills), the wrapper reads and follows both sibling `grilling` and
   `domain-modeling` `SKILL.md` files. This covers Pi without a nested skill tool
   and harnesses that reject nested invocation. All three remain user-only.
   The generator smoke check verifies the written fallback contract and reads
   its generated targets; it does not prove a real interactive harness follows
   that contract.
3. The `resolving-merge-conflicts` safety patch replaces the absolute
   `never --abort` rule. It continues a clearly intended operation despite
   difficulty, but stops for a human decision when context cannot establish
   whether the merge or rebase itself should continue.

The two content patches are fail-closed: each exact pinned upstream preimage
must occur exactly once, or generation stops rather than silently omitting or
misapplying the adaptation. Metadata parsing and post-patch validation likewise
stop on malformed or contradictory invocation policy. This protects
portability and merge safety, but it imposes a deliberate cost on every
upstream update: a maintainer must inspect upstream changes, confirm that each
local policy is still needed and semantically correct, and update an exact
preimage only when the new upstream text has been understood.

Review every manual or Renovate update as behavior, not merely as generated
files:

1. Confirm the new tag and peeled commit are the intended immutable source and
   inspect every changed selected skill and support file.
2. Re-evaluate all six install decisions and their invocation policies,
   especially upstream trigger-description or metadata changes.
3. Review each local adaptation against the new upstream behavior. Treat a
   failed preimage as a required review, not a reason to weaken the guard.
4. Confirm `UPSTREAM.md`, licenses, checksums, selected file sets, and the
   portability fallback are correct; check that no unexpected executable or
   symlink behavior was introduced.
5. Run the updater tests and synchronization check, then the repository's
   relevant Ansible and whitespace checks before merging.

## Ideas retained from skipped skills

These ideas can improve the current harness without installing the source skill.

### From `ask-matt`

Make context-management decisions at phase boundaries. Prefer continuing when
the next phase needs the current reasoning as a primary source. Use a handoff
only when context must move to another harness, directory, session, or person.

### From `to-spec`

Before implementation, identify the highest practical boundary at which the
intended behavior can be observed. Prefer an existing seam and use as few test
seams as practical. Record meaningful exclusions as part of the design.

### From `to-tickets`

- Split large work into independently observable vertical slices.
- State real blocking relationships between slices.
- Use expand-migrate-contract for wide mechanical refactors.
- Require each acceptance criterion to be false before its implementation
  starts.

### From `code-review`

Review a change against two separate questions:

1. Does it follow repository standards?
2. Does it implement the intended behavior without omissions or scope creep?

Prefer a fresh review context. Require citations for findings. Consider adding
these explicit axes to `z-review` rather than installing another review skill.

### From `wayfinder`

- Define the destination before decomposing a large effort.
- Separate known decisions, actionable questions, unresolved uncertainty, and
  explicit exclusions.
- Do not create detailed plans for work that is not yet understood.
- Use focused research or disposable prototypes to resolve uncertainty before
  implementation.

### From `prototype`

- Prototype only when discussion cannot answer a specific design question.
- State the question in one sentence before building.
- Use the cheapest runnable artifact that can answer it.
- Do not let disposable code become production code by momentum.
- Preserve the decision and evidence only when future work needs them.

### From `research`

- Frame a narrow, answerable research question.
- Prefer the source that owns the fact and cite consequential claims.
- Verify a sample of citations before relying on the report.
- Persist research only when another session or person needs it.
- Give delegated research an explicit stopping condition and spawn limit.

### From `improve-codebase-architecture`

- Review architecture in areas affected by planned or repeated changes.
- Prefer modules with small interfaces and substantial hidden behavior.
- Use the deletion test before adding or preserving wrappers.
- Tie refactoring to a concrete reduction in implementation or testing cost.
- Permit "no worthwhile refactor found" as a valid result.

### From `diagnosing-bugs`

Strengthen the existing debugging workflow rather than installing a duplicate:

- For difficult bugs, establish one named command that detects the exact
  symptom before forming hypotheses.
- Minimize the reproduction and rank multiple falsifiable hypotheses.
- Tag temporary instrumentation and verify its removal.
- Redact secrets from commands, outputs, and captured artifacts.
- Do not add a regression test at a seam that cannot reproduce the real bug.

### From `triage`

- Verify an incoming claim before marking it agent-ready.
- Search for existing behavior and prior rejection before creating work.
- Write durable briefs in terms of behavior and contracts, not line numbers.
- Treat "implemented" and "confirmed effective" as separate states.

### From `wizard`

- Automate directly before asking a human to act.
- Use browser automation when authorized and practical.
- Keep secrets out of chat when hidden local input or a credential store works.
- Create an interactive setup script only for a repeatable, multi-step human
  procedure.
- Put confirmation gates before irreversible manual actions.

### From `handoff`

Strengthen `z-create-handoff` rather than installing a duplicate:

- Tailor the handoff to the next session's specific purpose.
- Reference existing specs, plans, commits, and diffs instead of duplicating
  them.
- Explicitly redact secrets and personal information.

## Follow-up: post-merge confirmation

The current workflow does not consistently confirm that a merged and shipped
change produced its intended operational or user-visible effect. This is not a
requirement for every pull request.

After the skill evaluation, consider a low-friction confirmation mechanism that:

- Is selected only for changes with a meaningful effect to observe.
- Defines the expected effect before merge.
- Runs after the change reaches the relevant environment.
- Collects empirical evidence at the highest practical seam.
- Reports success, failure, or insufficient evidence.
- Has a clear owner and bounded follow-up behavior.

This is distinct from pre-merge tests, specification review, and CI status.
