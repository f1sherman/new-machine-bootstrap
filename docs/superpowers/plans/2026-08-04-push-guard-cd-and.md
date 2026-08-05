# Push Guard `cd &&` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use engineering:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow an implicit push from a feature-branch repository reached with `cd ... &&` without weakening direct-main protection.

**Architecture:** Preserve shell separators while parsing command segments. Exclusive `cd ... &&` narrowing is eligible only for an immediate, top-level push after a static directory change, with strict direct-Git repository selection and successful probes that prove every selected target is on a known non-main branch. Standalone static direct `git -C` remains a separate understood-selection path only when no prior directory transition occurred and successful probes identify every selected branch. All unsupported, unknown, or denied paths preserve the untransformed conservative directory candidate union, with only statically understood `git -C` targets added to that union.

**Tech Stack:** TypeScript-flavored Pi extension JavaScript, Node.js assertion harness, Bash

## Global Constraints

- This repository is public. Use only generic repository and branch names in code, tests, commits, and the PR.
- Preserve both directory candidates for `;` chains because a failed `cd` leaves the shell in the prior directory.
- Narrow only the `&&` path where the push can run only after the directory change succeeds.
- Replace the starting candidate for standalone static direct `git -C` only when no prior directory transition occurred and every selected target has a successfully probed known branch.

---

### Task 1: Make push directory candidates separator-aware

**Files:**
- Modify: `roles/common/files/pi/extensions/managed-hooks.ts:300-480`
- Test: `tests/pi-managed-hooks.sh:1636-1800`

**Interfaces:**
- Consumes: `splitShellSegments(command)`, `changedDirectoryCandidates(segment, cwd)`, and `pushMainBlockReason(pi, command, cwd)`.
- Produces: separator-aware shell steps for `pushMainBlockReason`; `splitShellSegments(command)` must continue to return command strings for existing callers.

**Reviewer Verification:**
- Run `bash tests/pi-managed-hooks.sh`. Expected output ends with `pi-managed-hooks checks complete`.
- Existing warning output from negative-path fixtures is expected.
- In a fresh Pi session after `bin/provision`, check generic temporary repositories on `main` and a feature branch. The five command forms in Step 5 must produce the expected allow/block decisions.

- [ ] **Step 1: Add the failing regression test**

In `tests/pi-managed-hooks.sh`, add an assertion in the push-guard section that starts in `/repo` (the harness main-branch repository), changes to `worktreeRoot` (the harness feature-branch repository), and expects this call to return `undefined`:

```js
const cdFeatureImplicitPush = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: `cd ${worktreeRoot} && git push` },
}, { cwd: "/repo" });
assert.equal(cdFeatureImplicitPush, undefined, "allows implicit push after required cd from main to feature repo");
```

Also add explicit assertions that:

```text
cd <main-repo> && git push       blocks from a feature-branch cwd
cd <main-repo>; git push         blocks from a feature-branch cwd
git -C <feature-repo> push       allows from a main-branch cwd
git -C <main-repo> push          blocks from a feature-branch cwd
```

Use only the existing generic harness paths `/repo` and `worktreeRoot`.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
bash tests/pi-managed-hooks.sh
```

Expected: FAIL only at `allows implicit push after required cd from main to feature repo`, with the actual value containing the direct-main block result.

- [ ] **Step 3: Preserve separators and narrow `&&` candidate propagation**

Add a parser helper that records each command segment and the separator that follows it. Keep `splitShellSegments(command)` as a compatibility wrapper that returns only command strings. Update only `pushMainBlockReason` to consume separator-aware steps.

Retain the conservative pre-`cd` and post-`cd` directory union while parsing. Track any immediate top-level `cd ... &&` separately from its eligible static targets. Narrow only when that marker and the eligible targets exist, the push and its separators are eligible, every direct Git selection is strictly static and understood, and successful target probes show that every selected target is on a known non-main branch. In that proven case, check only the understood selected targets.

Keep standalone static direct `git -C` as its own understood-selection path, independent of the immediate `cd ... &&` exemption. Permit that standalone replacement only when no prior `cd` created directory transition candidates and successful probes identify every selected target branch. Fail closed when a selected root or branch is unknown. For all unsupported or denied cases, check the untransformed conservative union and add only statically understood `git -C` selected targets. Never replace the original candidates in fallback mode. This applies to `;`, `||`, `|`, `|&`, newlines, parentheses, final segments, dynamic operands, wrappers, unsupported Git global options, and failed repository or branch probes. Keep shell-wrapper recursion scoped as it is now.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run:

```bash
bash tests/pi-managed-hooks.sh
```

Expected: PASS with the final line `pi-managed-hooks checks complete`. Existing negative-path fixture warnings are expected.

- [ ] **Step 5: Verify all acceptance paths empirically**

Use temporary generic Git repositories with one checkout on `main` and one checkout on a feature branch. Exercise the extension through its registered `tool_call` hook from both starting branches. Confirm:

```text
main cwd    + cd <feature> && git push  -> allow
feature cwd + cd <main> && git push     -> block
feature cwd + cd <main>; git push       -> block
main cwd    + git -C <feature> push     -> allow
feature cwd + git -C <main> push        -> block
```

Record the exact command and result in the task report.

- [ ] **Step 6: Commit**

Stage only:

```bash
git add docs/superpowers/plans/2026-08-04-push-guard-cd-and.md \
  roles/common/files/pi/extensions/managed-hooks.ts \
  tests/pi-managed-hooks.sh
git commit -m "fix(pi): scope push guard after cd and"
```
