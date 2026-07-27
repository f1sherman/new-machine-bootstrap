# Protect Ignored Superpowers Docs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent the managed commit workflow from committing ignored `docs/superpowers/` files while preserving normal commits and force-add support elsewhere.

**Architecture:** Enforce the policy inside both source copies of the managed commit wrapper, before any staging occurs. Keep the existing Pi and Claude command hooks as defense in depth, and align repository and agent guidance with the wrapper's behavior.

**Tech Stack:** Bash, Git, Ansible-managed skill files, repository shell tests

## Global Constraints

- Block only ignored inputs inside the current repository's `docs/superpowers/` directory.
- Allow nonignored `docs/superpowers/` files to commit normally.
- Preserve `--force` for ignored files outside `docs/superpowers/`.
- Do not install or configure a global Git hook.
- Do not change upstream Superpowers skills.
- Remove `.coding-agent/` only as an alternative location in the repository spec/plan commit rule; complete removal belongs to a separate pull request.
- Make all source changes inside this repository and deploy them only through `bin/provision`.

---

## File Structure

- `tests/commit-force-add-superpowers.sh` — disposable-repository behavior tests for both managed commit-wrapper source copies.
- `roles/common/files/config/skills/common/_commit/commit.sh` — wrapper deployed for Claude and Codex.
- `roles/common/files/config/skills/pi/z-commit/commit.sh` — wrapper deployed for Pi.
- `roles/common/files/config/skills/codex/_commit/SKILL.md` — Codex commit-worker instructions.
- `roles/common/files/config/skills/pi/z-commit/SKILL.md` — Pi commit-worker instructions.
- `roles/common/templates/dotfiles/claude/agents/_committer.md` — Claude committer instructions.
- `AGENTS.md` — repository-local spec and plan policy.

### Task 1: Enforce the ignored-superpowers boundary in commit wrappers

**Files:**
- Create: `tests/commit-force-add-superpowers.sh`
- Modify: `roles/common/files/config/skills/common/_commit/commit.sh`
- Modify: `roles/common/files/config/skills/pi/z-commit/commit.sh`

**Interfaces:**
- Consumes: existing `commit.sh [-f|--force] -m <message> <files...>` CLI.
- Produces: the same CLI, with a pre-staging rejection for ignored repository-relative `docs/superpowers` inputs.

- [ ] **Step 1: Write the failing behavior test**

Create an executable Bash test that loops over both wrapper source paths. For each wrapper, create fresh temporary Git repositories and assert these behaviors:

```bash
scripts=(
  "$repo_root/roles/common/files/config/skills/common/_commit/commit.sh"
  "$repo_root/roles/common/files/config/skills/pi/z-commit/commit.sh"
)

# Rejected cases, each in a fresh repository whose .gitignore contains
# /docs/superpowers/:
# - docs/superpowers/specs/design.md with --force
# - ./docs/superpowers/specs/design.md with --force
# - the absolute path to docs/superpowers/specs/design.md with --force
# - normal.txt plus docs/superpowers/specs/design.md with --force
# Assert nonzero status, no new commit, and an empty index after each rejection.

# Allowed cases, each in a fresh repository:
# - docs/superpowers/specs/design.md when it is not ignored
# - ignored/generated.txt with --force
# Assert a new commit containing the requested file.
```

Use `mktemp -d`, a cleanup trap, local Git user configuration, and small assertion helpers. Invoke each wrapper with `bash "$script"` so executable mode is not required to establish the initial red test.

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
bash tests/commit-force-add-superpowers.sh
```

Expected: the first ignored-superpowers case fails because the wrapper currently creates the commit instead of rejecting it.

- [ ] **Step 3: Implement repository-relative path classification before staging**

In each wrapper, extend the existing ignored-file pre-check:

```bash
repo_root=$(cd "$(git rev-parse --show-toplevel)" && pwd -P)
ignored_files=()
ignored_superpowers_files=()

for file in "${files[@]}"; do
    if [[ -e "$file" ]] && git check-ignore -q "$file" 2>/dev/null; then
        ignored_files+=("$file")

        if [[ "$file" = /* ]]; then
            absolute_file="$file"
        else
            absolute_file="$(pwd -P)/$file"
        fi
        absolute_file="$(cd "$(dirname "$absolute_file")" && pwd -P)/$(basename "$absolute_file")"

        case "$absolute_file" in
            "$repo_root/docs/superpowers"|"$repo_root/docs/superpowers/"*)
                ignored_superpowers_files+=("$file")
                ;;
        esac
    fi
done
```

Immediately after collection and before the generic ignored-file check, reject any protected inputs regardless of `--force`:

```bash
if [[ ${#ignored_superpowers_files[@]} -gt 0 ]]; then
    echo "Error: Ignored docs/superpowers files are local working documents and cannot be force-added:" >&2
    for f in "${ignored_superpowers_files[@]}"; do
        echo "  $f" >&2
    done
    exit 1
fi
```

Keep both wrapper copies identical after the edit.

- [ ] **Step 4: Run wrapper behavior tests**

Run:

```bash
bash tests/commit-force-add-superpowers.sh
cmp roles/common/files/config/skills/common/_commit/commit.sh \
  roles/common/files/config/skills/pi/z-commit/commit.sh
```

Expected: all cases pass and `cmp` exits zero.

- [ ] **Step 5: Commit the wrapper and tests**

Invoke the `z-commit` skill for:

```text
tests/commit-force-add-superpowers.sh
roles/common/files/config/skills/common/_commit/commit.sh
roles/common/files/config/skills/pi/z-commit/commit.sh
```

Use an imperative message such as `Block force-adding ignored superpowers docs`.

### Task 2: Align active commit guidance

**Files:**
- Modify: `roles/common/files/config/skills/codex/_commit/SKILL.md`
- Modify: `roles/common/files/config/skills/pi/z-commit/SKILL.md`
- Modify: `roles/common/templates/dotfiles/claude/agents/_committer.md`
- Modify: `AGENTS.md`

**Interfaces:**
- Consumes: the wrapper policy established by Task 1.
- Produces: consistent agent instructions that never request the rejected operation.

- [ ] **Step 1: Update the commit-worker instructions**

In the Codex and Pi commit skills, replace the unconditional force retry with:

```text
If `commit.sh` fails only because a file is gitignored, rerun the same command with `--force`, except never force-add an ignored file under `docs/superpowers/`; leave those local and omit them from the commit.
```

In the Claude committer template, make the equivalent change while retaining its existing bullet style and `-f` alias reference.

- [ ] **Step 2: Update repository-local guidance**

Replace the current repository rule with:

```markdown
- **Commit specs and plans unless ignored**: Design specs and implementation plans belong under `docs/superpowers/`. Before committing them, run `git check-ignore -q docs/superpowers`; when ignored, keep them local and never use `git add -f` or `--force` on them.
```

This removes `.coding-agent/` only from the active spec/plan-location rule. Do not broaden this task into deleting legacy `.coding-agent/` workflows.

- [ ] **Step 3: Verify guidance consistency**

Run:

```bash
rg -n 'fails.*gitignored|retry.*--force|Always commit specs|\.coding-agent/' \
  AGENTS.md \
  roles/common/files/config/skills/codex/_commit/SKILL.md \
  roles/common/files/config/skills/pi/z-commit/SKILL.md \
  roles/common/templates/dotfiles/claude/agents/_committer.md
```

Expected: each force-retry instruction includes the `docs/superpowers/` exception; `AGENTS.md` contains no `.coding-agent/` alternative.

- [ ] **Step 4: Commit guidance changes**

Invoke the `z-commit` skill for the four guidance files with an imperative message such as `Align commit guidance with ignored docs policy`.

### Task 3: Verify and deploy the complete behavior

**Files:**
- Modify only if verification exposes a defect in files from Tasks 1-2.

**Interfaces:**
- Consumes: wrapper enforcement and aligned guidance.
- Produces: tested source, provisioned managed files, and end-to-end evidence for the pull request.

- [ ] **Step 1: Run focused source tests**

Run:

```bash
bash tests/commit-force-add-superpowers.sh
bash tests/pi-managed-hooks.sh
bash roles/common/files/claude/hooks/block-force-add-superpowers-docs.sh.test
```

Expected: all suites pass. If the Claude hook test is absent on the current branch, verify the hook manually with representative allow and deny JSON payloads and record that substitution for the pull request.

- [ ] **Step 2: Run static checks**

Run:

```bash
bash -n \
  tests/commit-force-add-superpowers.sh \
  roles/common/files/config/skills/common/_commit/commit.sh \
  roles/common/files/config/skills/pi/z-commit/commit.sh
git diff --check origin/main...HEAD
```

Expected: all commands exit zero.

- [ ] **Step 3: Provision from the feature worktree**

Run:

```bash
bin/provision
```

Expected: provisioning completes successfully and deploys the managed Pi, Claude, and Codex commit files from this worktree.

- [ ] **Step 4: Verify deployed behavior end to end**

In disposable repositories, invoke `~/.pi/agent/skills/z-commit/commit.sh` and verify:

```text
ignored docs/superpowers file + --force -> rejected, no commit, empty index
nonignored docs/superpowers file -> committed
unrelated ignored file + --force -> committed
```

Also compare the deployed Pi wrapper to its repository source:

```bash
cmp ~/.pi/agent/skills/z-commit/commit.sh \
  roles/common/files/config/skills/pi/z-commit/commit.sh
```

Expected: behavior matches the source tests and `cmp` exits zero.

- [ ] **Step 5: Review the final diff and repository state**

Run:

```bash
git status --short
git diff --stat origin/main...HEAD
git diff origin/main...HEAD
git log --oneline origin/main..HEAD
```

Expected: only the approved spec, plan, wrapper tests, wrapper implementations, and guidance changes are present; the worktree is clean.

- [ ] **Step 6: Push and open the pull request**

Push `protect-ignored-superpowers-docs`, open a pull request against `main`, and include the observed regression, wrapper bypass, focused tests, provisioning result, and deployed end-to-end verification.
