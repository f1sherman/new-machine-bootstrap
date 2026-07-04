# Pi global AGENTS fragment design

## Goal

Let NMB own generic Pi global instruction plumbing without knowing about HNP-specific PR workflows. Downstream repos such as HNP should be able to add global Pi guidance and repo-start reminders through neutral extension points.

## Non-goals

- Do not hardcode HNP, Forgejo, or `pull-request` behavior in NMB.
- Do not add heuristic PR auto-creation to Pi.
- Do not change the existing repo-start callback contract except where needed to document or verify its use.
- Do not remove Claude or Codex global instruction behavior.

## Assumptions

- Pi reads `~/.pi/agent/AGENTS.md` as a global context file.
- NMB already assembles Claude's global `~/.claude/CLAUDE.md` from sorted fragments and links Codex global instructions to that assembled file.
- NMB already owns generic `repo-start` and runs executable callbacks under `~/.local/bin/repo-start.d`.
- HNP owns personal PR workflow skills and can install HNP-specific fragments or callbacks into NMB-owned extension points.

## Approaches considered

### Recommended: NMB fragment assembly plus downstream fragments

NMB creates a Pi global context fragment directory, assembles `~/.pi/agent/AGENTS.md` from sorted fragments, and installs only generic NMB-owned guidance. Downstream provisioning can install extra fragments into the same directory. HNP can add a fragment that tells Pi to invoke its `pull-request` skill after verified changes are ready, without NMB knowing about that skill.

This matches the existing Claude fragment pattern, keeps ownership boundaries clean, and uses Pi's built-in context-file behavior instead of an extension or heuristic.

### Alternative: NMB hardcodes PR guidance

NMB could add a global Pi instruction that names `pull-request`. This is simple but leaks HNP-specific workflow policy into a generic bootstrap repo. It also creates an ownership mismatch because the skill and PR workflow are maintained elsewhere.

### Alternative: HNP-only Pi extension

HNP could inject the instruction through a Pi extension. That keeps NMB clean, but it duplicates a built-in Pi context mechanism and makes global guidance less visible than a normal `AGENTS.md` file.

## Design

NMB should manage Pi global instructions the same way it manages Claude global instructions:

1. Create `~/.pi/agent/AGENTS.md.d`.
2. Install an NMB-owned base fragment if useful for generic Pi behavior.
3. Assemble sorted fragments into `~/.pi/agent/AGENTS.md`.
4. Leave the fragment directory open for downstream repos to install additional fragments.

NMB's base fragment must stay provider- and workflow-neutral. It may include generic work style or safety guidance, but it must not mention HNP, Forgejo, GitHub PR routing, or a personal PR skill.

HNP should use two NMB-owned extension points:

1. Install a Pi AGENTS fragment with personal PR completion guidance, naming Pi's `pull-request` skill.
2. Install a `repo-start.d` callback that prints a concise reminder after a work branch/worktree starts.

The repo-start callback remains generic from NMB's perspective: NMB only executes callbacks with repo, branch, main branch, and status arguments. The downstream callback owns any message content.

## Components and boundaries

- **NMB Pi AGENTS assembly**: Creates and assembles global Pi context fragments.
- **NMB repo-start callbacks**: Already execute downstream callbacks after successful repo-start operations.
- **HNP Pi guidance fragment**: Contains HNP-specific `pull-request` completion guidance.
- **HNP repo-start reminder callback**: Prints the HNP-specific reminder when a repo-start operation succeeds.
- **HNP PR workflow skills**: Continue to own PR creation, proof, and monitoring.

## Data flow

1. NMB provisioning creates or updates the global Pi fragment directory and assembled `AGENTS.md`.
2. HNP provisioning installs an HNP-specific fragment into that directory.
3. Pi loads the assembled global `AGENTS.md` at startup or after `/reload`.
4. When a user starts work with `repo-start`, NMB's existing callback runner invokes any HNP callback.
5. Pi sees both startup guidance and just-in-time repo-start reminder, then invokes the downstream `pull-request` skill when verified code changes are ready.

## Error handling

- If the fragment directory contains no downstream fragments, NMB still assembles a valid global Pi context file or leaves a minimal file.
- If a repo-start callback fails, existing repo-start callback failure behavior should continue to surface the failing callback.
- If HNP is not installed, no HNP-specific PR guidance appears.
- If the user explicitly asks not to create a PR, downstream guidance should say to respect that opt-out.

## Testing and verification

- Add or update NMB tests to verify provisioning includes Pi global AGENTS fragment assembly and does not hardcode HNP-specific PR guidance.
- Add or update NMB repo-start callback tests only if the existing callback contract lacks coverage for downstream reminder callbacks. The existing callback runner should remain the primary extension point.
- In HNP, test that personal-dev installs a Pi AGENTS fragment and a repo-start callback without requiring NMB to know the message content.
- Verify Pi documentation or behavior confirms `~/.pi/agent/AGENTS.md` is the global context file.

## Rollout

Provision NMB first to create the generic Pi fragment assembly point. Provision HNP afterward to install the HNP-specific fragment and callback. Existing Pi sessions need `/reload` or restart to read the updated global context file.

## Spec self-review

- Placeholder scan: no placeholders remain.
- Internal consistency: NMB owns only generic extension points; HNP owns specific PR guidance.
- Scope check: this is split into one NMB implementation and one HNP implementation using the new NMB extension point.
- Ambiguity check: the boundary is explicit: NMB must not name HNP or `pull-request`; HNP may name `pull-request` in its own fragment and callback.
