---
name: _pull-request
description: Create a pull request on the primary origin remote by routing to the Forgejo or GitHub PR workflow.
---

# Create Pull Request

## Process

1. Resolve the agent worktree path explicitly. If you already know the absolute repo path, keep using it. Otherwise run:
   ```bash
   REPO_DIR="$(bash ~/.local/share/skills/_pr-workflow-common/agent-worktree-path.sh)"
   ```
2. If `git -C "$REPO_DIR" status --porcelain --untracked-files=normal` is non-empty, invoke `_commit` before continuing. The PR and proof must only cover committed branch content.
3. Recheck `git -C "$REPO_DIR" status --porcelain --untracked-files=normal` and stop if the worktree is still dirty.
4. Run `bash ~/.local/share/skills/_pr-workflow-common/context.sh "$REPO_DIR"` and capture the JSON as `CONTEXT_JSON`.
5. Extract `REPO_DIR="$(echo "$CONTEXT_JSON" | jq -r '.repo_dir')"` and `BRANCH="$(echo "$CONTEXT_JSON" | jq -r '.branch')"` and `BASE="$(echo "$CONTEXT_JSON" | jq -r '.base')"` and `PLATFORM="$(echo "$CONTEXT_JSON" | jq -r '.platform')"`.
6. Reject the request if `BRANCH` already matches `BASE`.
7. Invoke `_review` with the resolved `REPO_DIR` and `BASE`, and let it classify and handle findings.
8. Recheck `git -C "$REPO_DIR" status --porcelain --untracked-files=normal` after `_review` and stop if the worktree is still dirty.
9. Run `bash ~/.local/share/skills/_pr-workflow-common/context.sh "$REPO_DIR"` again and capture the refreshed JSON as `CONTEXT_JSON`.
10. Extract `REPO_DIR="$(echo "$CONTEXT_JSON" | jq -r '.repo_dir')"` and `BRANCH="$(echo "$CONTEXT_JSON" | jq -r '.branch')"` and `BASE="$(echo "$CONTEXT_JSON" | jq -r '.base')"` and `PLATFORM="$(echo "$CONTEXT_JSON" | jq -r '.platform')"`.
11. Reject the request if `BRANCH` already matches `BASE`.
12. Draft `PR_TITLE` separately from `PR_BODY`.
13. Build the shared PR body once with the helper's real CLI:
   ```bash
   CONTEXT_JSON_PATH="$(mktemp)"
   printf '%s\n' "$CONTEXT_JSON" > "$CONTEXT_JSON_PATH"
   PR_BODY="$(bash ~/.local/share/skills/_pr-workflow-common/build-pr-body.sh \
     --context-json "$CONTEXT_JSON_PATH" \
     --summary "$PR_SUMMARY" \
     --why "$PR_WHY" \
     --evidence "$PR_EVIDENCE_1" \
     --evidence "$PR_EVIDENCE_2" \
     --approach "$PR_APPROACH" \
     --verification "$PR_VERIFICATION_1" \
     --verification "$PR_VERIFICATION_2" \
     --reviewer-notes "$PR_REVIEWER_NOTES")"
   ```
14. Use this body contract with four required core sections in this order:
   - `Summary`
   - `Why`
   - `Approach`
   - `Verification`
   Reviewer notes may appear only as an optional final section appended after those four core sections.
15. Keep `Why` to 1-2 short paragraphs. Include concrete evidence when available.
16. Keep `Approach` to 1-2 short paragraphs or short bullets.
17. Keep `Verification` to short bullets and state plainly when verification was not run.
18. If `PLATFORM` is `forgejo`, delegate to `_pr-forgejo`.
19. If `PLATFORM` is `github`, delegate to `_pr-github`.
20. Pass the refreshed shared context plus `PR_TITLE` and `PR_BODY` forward unchanged so the platform skill does not repeat branch checks, context gathering, title drafting, or body authoring.
21. Let the platform skill create or reuse the PR and post proof from the same worktree.
22. After the platform skill returns, verify that the remote PR head SHA matches local `HEAD`.
23. Check remote PR statuses for the pushed head and report pending or failed checks honestly.
24. Report the PR URL, PR number, head SHA comparison, and remote status summary. Do not enter a foreground PR loop. For Forgejo PRs, pr-upkeeper owns ongoing comments, checks, conflicts, and stale branch upkeep. For GitHub PRs, report only the immediate remote state/status checked by this workflow.

## Existing PR Updates

Treat initial PR creation and existing PR updates as separate workflow states. The numbered process above creates or reuses the PR, posts proof, and reports the remote head/status state once. After any file change while working on an open PR, keep the already-open PR synchronized before reporting it as current.

Required post-PR update flow:

1. Run the verification relevant to the follow-up file changes.
2. If `git -C "$REPO_DIR" status --porcelain --untracked-files=normal` is non-empty, invoke `_commit` so the changed files become part of the PR branch.
3. Recheck `git -C "$REPO_DIR" status --porcelain --untracked-files=normal` and stop if the worktree is still dirty.
4. Push the current branch `HEAD` to the existing PR branch explicitly.
5. Verify that the remote PR head SHA matches local `HEAD` before saying the PR is current.
6. Check remote PR statuses for the pushed head and report pending or failed checks honestly.
7. Refresh proof, comments, and the PR body when the follow-up change materially changes implementation behavior, verification evidence, or reviewer-facing context.
8. Always update the PR description when follow-up file changes make it out of date or incorrect.

Do not describe an existing PR as current until the remote branch points at local `HEAD` and remote statuses have been checked for that pushed head.

## Important

- Platform detection uses the `origin` remote only.
- Use `_commit` to normalize dirty branch content before PR creation so the posted proof matches the branch `HEAD`.
- Review is centralized in `_review`; this skill only delegates there before continuing PR setup.
- Base-branch resolution uses an explicit helper argument when provided; otherwise it resolves `origin/HEAD`, then falls back to a local `main`, `master`, or `trunk`.
- Do not guess from `$(pwd)` and do not scan sibling worktrees. Use the explicit worktree path for this agent.
- `bash ~/.local/share/skills/_pr-workflow-common/agent-worktree-path.sh` reads the pane-local `tmux-agent-worktree` state published by `worktree-start` or `tmux-agent-worktree set <absolute-path>`.
- `bash ~/.local/share/skills/_pr-workflow-common/detect-platform.sh "$REPO_DIR"` remains available when you need to inspect the platform independently, but the shared context already includes `platform`.
- Legacy remotes such as Bitbucket do not affect routing.
- Review is centralized in `_review`; this skill only delegates there before continuing PR setup.
- This skill owns dirty-tree normalization, shared context gathering, `PR_TITLE` drafting, and PR body authoring.
- The platform skill owns PR creation and demo posting. It must consume `PR_TITLE` and `PR_BODY` unchanged.
- Ongoing Forgejo PR upkeep is handled outside this skill by pr-upkeeper; do not start a blocking PR watch loop here. GitHub PRs need a separate upkeep path if ongoing follow-up is required.
