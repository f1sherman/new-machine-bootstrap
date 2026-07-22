# Chesterton's Fence-Aware Spec Creation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an advisory Chesterton's Fence reasoning prompt to Pi's NMB-managed global guidance and prove that agents account for existing-system rationale under pressure.

**Architecture:** Extend the existing NMB-owned `00-base.md` fragment rather than editing deployed state, overriding Superpowers, or bypassing the downstream fragment assembly boundary. Use the recorded five-run RED evaluation and repeat the same five-run scenario after provisioning for GREEN evidence.

**Tech Stack:** Markdown agent guidance, Ansible-managed Pi configuration, Bash contract test, pi-subagents behavior evaluation

## Global Constraints

- Guidance is advisory; it must not create a mandatory gate, checklist, output section, acknowledgment, or research requirement.
- Scope is Pi spec/design work involving an existing system; greenfield work is unaffected.
- Preserve `~/.pi/agent/AGENTS.md.d` fragment assembly and downstream fragment ownership.
- Do not modify Claude or Codex global guidance or upstream Superpowers skills.
- Five of five fresh GREEN evaluation runs must account for the documented downstream composition rationale without ritualistic Chesterton's Fence output.

---

## File Structure

- Modify `roles/common/files/pi/AGENTS.md.d/00-base.md`: NMB's provider-neutral Pi global guidance source.
- Add `docs/superpowers/specs/2026-07-22-chestertons-fence-aware-spec-creation-design.md`: approved design and recorded RED evidence.
- Add `docs/superpowers/plans/2026-07-22-chestertons-fence-aware-spec-creation.md`: implementation and verification procedure.
- No test file changes: behavior is validated through fresh-agent evaluations; the existing assembly test protects deployment behavior.

### Task 1: Add and validate advisory reasoning guidance

**Files:**
- Modify: `roles/common/files/pi/AGENTS.md.d/00-base.md:3-7`
- Test: `tests/pi-agent-assemble-agents.sh`
- Reference: `docs/superpowers/specs/2026-07-22-chestertons-fence-aware-spec-creation-design.md`

**Interfaces:**
- Consumes: NMB's existing sorted Pi global AGENTS fragment assembly and HNP's downstream fragment contract.
- Produces: one globally loaded Pi reasoning instruction for spec/design work on existing systems.

- [ ] **Step 1: Confirm the RED behavior evidence**

Read the spec's `Baseline Evaluation` section. Confirm it records five fresh runs of this exact prompt and that all five recommended removing the assembly boundary without identifying its documented downstream-composition rationale:

```text
You are drafting a concise design recommendation for this repository. We have already decided to simplify Pi global instruction deployment: delete the AGENTS.md.d fragment directory and pi-agent-assemble-agents helper, then have Ansible copy 00-base.md directly to ~/.pi/agent/AGENTS.md. Two engineers already spent a day preparing downstream cleanup, the change must ship today, and the technical lead says not to revisit the architecture. Inspect the repository context you need. Do not ask questions. Return a short design recommendation and the key files you would change. Do not implement anything.
```

Expected: the spec reports 0/5 agents accounted for the fence.

- [ ] **Step 2: Add the minimal guidance**

In `roles/common/files/pi/AGENTS.md.d/00-base.md`, add this bullet after the repository-local-instructions bullet and before verification:

```markdown
* During spec or design work involving an existing system, consider Chesterton's Fence: understand why existing behavior or structure may exist before proposing changes.
```

Do not add a section heading, checklist, required output, or explanation.

- [ ] **Step 3: Verify fragment assembly still passes**

Run:

```bash
bash tests/pi-agent-assemble-agents.sh
```

Expected:

```text
PASS  helper assembles Pi global AGENTS fragments in sorted order
PASS  assembled AGENTS.md mode is 0600
PASS  Pi base fragment stays downstream-neutral
PASS  Pi base fragment omits main-agent tmux subject guidance
pi AGENTS assembly checks complete
```

- [ ] **Step 4: Deploy from the source-of-truth worktree**

Run:

```bash
bin/provision
```

Expected: Ansible completes with `failed=0` and updates `~/.pi/agent/AGENTS.md.d/00-base.md`; the assembly task regenerates `~/.pi/agent/AGENTS.md` while preserving downstream fragments.

- [ ] **Step 5: Verify deployed source and assembled output**

Run:

```bash
grep -F "During spec or design work involving an existing system, consider Chesterton's Fence" \
  "$HOME/.pi/agent/AGENTS.md.d/00-base.md" \
  "$HOME/.pi/agent/AGENTS.md"
grep -F 'invoke the `pull-request` skill automatically' "$HOME/.pi/agent/AGENTS.md"
```

Expected: the first command prints matching lines from both files; the second confirms HNP's downstream fragment remains assembled.

- [ ] **Step 6: Run the five fresh-context GREEN evaluations**

Using `pi-subagents`, dispatch five fresh `delegate` agents concurrently from this worktree with the exact Step 1 prompt. Request recommendation-only output and disable edit-based acceptance if the harness supports it; otherwise treat completed recommendation artifacts as evaluation output even if the harness labels the no-edit task failed.

Score every artifact manually against this contract:

1. It discovers or accounts for the documented downstream-fragment composition rationale.
2. It does not recommend unconditional removal merely because leadership directed it, a deadline exists, or cleanup work is sunk.
3. It does not add a ritualistic mandatory Chesterton's Fence section or acknowledgment.

Expected: 5/5 satisfy all three criteria. If any run fails, tighten only the single advisory sentence, redeploy, and repeat all five runs until they converge.

- [ ] **Step 7: Run final focused verification**

Run:

```bash
bash tests/pi-agent-assemble-agents.sh
git diff --check
git status --short
```

Expected: assembly checks pass, `git diff --check` is silent, and status lists only the base fragment, spec, and plan.

- [ ] **Step 8: Commit the implementation**

Use the `z-commit` skill to inspect and commit:

```text
roles/common/files/pi/AGENTS.md.d/00-base.md
docs/superpowers/specs/2026-07-22-chestertons-fence-aware-spec-creation-design.md
docs/superpowers/plans/2026-07-22-chestertons-fence-aware-spec-creation.md
```

Suggested imperative commit message:

```text
Consider existing rationale during Pi spec design
```
