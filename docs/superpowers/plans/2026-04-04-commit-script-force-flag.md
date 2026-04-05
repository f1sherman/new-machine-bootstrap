# commit.sh --force Flag Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `--force` / `-f` flag to `commit.sh` so it can stage and commit gitignored files when explicitly requested.

**Architecture:** Add flag parsing for `--force`, pre-check files against `git check-ignore` before staging, and conditionally use `git add --force` for gitignored files. Fail with a helpful message when gitignored files are detected without `--force`.

**Tech Stack:** Bash, Git

---

### Task 1: Write test script for commit.sh

**Files:**
- Create: `tmp/test-commit-sh.sh`

The test script creates a disposable git repo in `/tmp`, sets up a `.gitignore`, and exercises four scenarios. It tests against whatever `commit.sh` is at the repo source path.

- [ ] **Step 1: Write the test script**

```bash
#!/bin/bash
#
# Test suite for commit.sh --force flag
# Creates a temp git repo and tests gitignore handling scenarios

set -e

COMMIT_SH="$(cd "$(dirname "$0")/.." && pwd)/roles/common/files/config/skills/common/committing-changes/commit.sh"
TEST_DIR=$(mktemp -d)
PASS=0
FAIL=0

cleanup() {
    rm -rf "$TEST_DIR"
    echo ""
    echo "Results: $PASS passed, $FAIL failed"
    if [[ $FAIL -gt 0 ]]; then
        exit 1
    fi
}
trap cleanup EXIT

setup_repo() {
    rm -rf "$TEST_DIR"
    TEST_DIR=$(mktemp -d)
    cd "$TEST_DIR"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"
    # Create an initial commit so HEAD exists
    echo "init" > README.md
    git add README.md
    git commit -q -m "initial"
    # Set up gitignore
    echo "ignored/" > .gitignore
    git add .gitignore
    git commit -q -m "add gitignore"
}

assert_exit_code() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"
    local output="$4"
    if [[ "$actual" -eq "$expected" ]]; then
        echo "PASS: $test_name"
        (( ++PASS ))
    else
        echo "FAIL: $test_name (expected exit $expected, got $actual)"
        echo "  Output: $output"
        (( ++FAIL ))
    fi
}

assert_output_contains() {
    local test_name="$1"
    local expected_substring="$2"
    local actual_output="$3"
    if echo "$actual_output" | grep -q "$expected_substring"; then
        echo "PASS: $test_name"
        (( ++PASS ))
    else
        echo "FAIL: $test_name (output did not contain: $expected_substring)"
        echo "  Output: $actual_output"
        (( ++FAIL ))
    fi
}

# ── Test 1: Normal (non-gitignored) files work without --force ──
echo "── Test 1: Normal files work without --force ──"
setup_repo
echo "hello" > normal.txt
output=$("$COMMIT_SH" -m "add normal file" normal.txt 2>&1) || true
# commit.sh also pushes, which will fail (no remote) — that's expected.
# Check that the commit was created by looking at git log.
if git log --oneline | grep -q "add normal file"; then
    echo "PASS: normal file committed successfully"
    (( ++PASS ))
else
    echo "FAIL: normal file was not committed"
    (( ++FAIL ))
fi

# ── Test 2: Gitignored file fails without --force ──
echo ""
echo "── Test 2: Gitignored file fails without --force ──"
setup_repo
mkdir -p ignored
echo "secret" > ignored/file.txt
exit_code=0
output=$("$COMMIT_SH" -m "add ignored file" ignored/file.txt 2>&1) || exit_code=$?
assert_exit_code "gitignored file exits non-zero without --force" 1 "$exit_code" "$output"
assert_output_contains "error message mentions --force" "\-\-force" "$output"
# Verify nothing was committed
commit_count=$(git log --oneline | wc -l | tr -d ' ')
if [[ "$commit_count" -eq 2 ]]; then
    echo "PASS: no commit was created"
    (( ++PASS ))
else
    echo "FAIL: unexpected commit count: $commit_count (expected 2)"
    (( ++FAIL ))
fi

# ── Test 3: Gitignored file succeeds with --force ──
echo ""
echo "── Test 3: Gitignored file succeeds with --force ──"
setup_repo
mkdir -p ignored
echo "secret" > ignored/file.txt
output=$("$COMMIT_SH" --force -m "add ignored file with force" ignored/file.txt 2>&1) || true
if git log --oneline | grep -q "add ignored file with force"; then
    echo "PASS: gitignored file committed with --force"
    (( ++PASS ))
else
    echo "FAIL: gitignored file was not committed with --force"
    echo "  Output: $output"
    (( ++FAIL ))
fi

# ── Test 4: Mixed gitignored + normal files fail without --force ──
echo ""
echo "── Test 4: Mixed files fail without --force (no partial staging) ──"
setup_repo
echo "normal" > normal.txt
mkdir -p ignored
echo "secret" > ignored/file.txt
exit_code=0
output=$("$COMMIT_SH" -m "mixed commit" normal.txt ignored/file.txt 2>&1) || exit_code=$?
assert_exit_code "mixed files exit non-zero without --force" 1 "$exit_code" "$output"
# Verify nothing was staged (no partial staging)
staged=$(git diff --cached --name-only)
if [[ -z "$staged" ]]; then
    echo "PASS: nothing was staged (no partial staging)"
    (( ++PASS ))
else
    echo "FAIL: files were partially staged: $staged"
    (( ++FAIL ))
fi
```

- [ ] **Step 2: Make the test script executable**

Run: `chmod +x tmp/test-commit-sh.sh`

- [ ] **Step 3: Run tests — expect failures for tests 2, 3, 4**

Run: `tmp/test-commit-sh.sh`

Expected: Test 1 passes. Tests 2-4 fail because the current `commit.sh` has no `--force` flag or gitignore pre-check.

---

### Task 2: Add --force flag to commit.sh

**Files:**
- Modify: `roles/common/files/config/skills/common/committing-changes/commit.sh`

- [ ] **Step 1: Add --force flag parsing**

In the argument parsing `case` block, add `-f|--force` before the `-*` catch-all. Also add the `force=false` variable initialization alongside the existing `message=""` and `files=()`.

Add after `files=()` (line 23):

```bash
force=false
```

Add as a new case before `-*)`:

```bash
        -f|--force)
            force=true
            shift
            ;;
```

Update the header comment to document the new flag. Replace lines 3-15:

```
# commit.sh - Create a git commit with specified files and message
#
# Usage:
#   commit.sh -m "message" file1 file2 ...
#   commit.sh --force -m "message" file1 file2 ...
#
# This script creates commits WITHOUT any AI co-author attribution.
# Commits appear as if authored solely by the user.
#
# Arguments:
#   -m, --message    Commit message (required)
#   -f, --force      Force-add files that match .gitignore patterns
#   file1 file2 ...  Files to stage and commit (at least one required)
#
# Example:
#   commit.sh -m "Add user authentication" src/auth.ts src/login.tsx
#   commit.sh --force -m "Add design doc" docs/spec.md
```

Update the help text in the `-h|--help` case to include the new flag. Replace the help echo block:

```bash
        -h|--help)
            echo "Usage: commit.sh [-f|--force] -m \"message\" file1 file2 ..."
            echo ""
            echo "Create a git commit with specified files and message."
            echo "No AI co-author attribution is added."
            echo ""
            echo "Arguments:"
            echo "  -m, --message    Commit message (required)"
            echo "  -f, --force      Force-add files that match .gitignore patterns"
            echo "  file1 file2 ...  Files to stage and commit (at least one required)"
            exit 0
            ;;
```

- [ ] **Step 2: Add gitignore pre-check before staging**

Replace the entire "Stage the specified files" section (lines 89-96) with gitignore pre-check and conditional staging:

```bash
# Pre-check: identify gitignored files
ignored_files=()
for file in "${files[@]}"; do
    if [[ -e "$file" ]] && git check-ignore -q "$file" 2>/dev/null; then
        ignored_files+=("$file")
    fi
done

# If gitignored files found without --force, fail with helpful message
if [[ ${#ignored_files[@]} -gt 0 && "$force" == "false" ]]; then
    echo "Error: The following files are gitignored and cannot be staged without --force:" >&2
    for f in "${ignored_files[@]}"; do
        echo "  $f" >&2
    done
    echo "" >&2
    echo "Use --force (-f) to commit these files anyway:" >&2
    echo "  commit.sh --force -m \"message\" file1 file2 ..." >&2
    exit 1
fi

# Stage the specified files
for file in "${files[@]}"; do
    if [[ -e "$file" ]]; then
        if [[ "$force" == "true" ]] && git check-ignore -q "$file" 2>/dev/null; then
            git add --force -- "$file"
        else
            git add -- "$file"
        fi
    else
        git rm -- "$file" 2>/dev/null || true
    fi
done
```

- [ ] **Step 3: Run tests — all should pass**

Run: `tmp/test-commit-sh.sh`

Expected: All 4 test groups pass. Output shows `Results: N passed, 0 failed`.

- [ ] **Step 4: Commit**

```bash
~/.claude/skills/committing-changes/commit.sh -m "Add --force flag to commit.sh for gitignored files" roles/common/files/config/skills/common/committing-changes/commit.sh
```

---

### Task 3: Update SKILL.md files to document --force

**Files:**
- Modify: `roles/common/files/config/skills/common/committing-changes/SKILL.md`
- Modify: `roles/common/files/config/skills/gsd/committing-changes/SKILL.md`

- [ ] **Step 1: Update common SKILL.md**

In `roles/common/files/config/skills/common/committing-changes/SKILL.md`, add a new section after "The commit.sh Script" section (after line 49). Insert before "## Important":

```markdown
## Handling Gitignored Files

If `commit.sh` fails because a file matches a `.gitignore` pattern, it will print the affected files and suggest using `--force`. Retry the same command with `--force` (`-f`) to stage those files:

```bash
# If this fails due to gitignored files:
commit.sh -m "Add design doc" docs/spec.md

# Retry with --force:
commit.sh --force -m "Add design doc" docs/spec.md
```
```

Also update the bullet list under "The commit.sh Script" to mention the flag. Add after the "Validates inputs and shows the result" bullet:

```markdown
- Supports `--force` (`-f`) to stage files that match `.gitignore` patterns
```

- [ ] **Step 2: Update GSD SKILL.md**

Apply the same two changes to `roles/common/files/config/skills/gsd/committing-changes/SKILL.md`:

Add the "Handling Gitignored Files" section before "## Important", and add the `--force` bullet to the script description list. Use the GSD path in examples:

```markdown
## Handling Gitignored Files

If `commit.sh` fails because a file matches a `.gitignore` pattern, it will print the affected files and suggest using `--force`. Retry the same command with `--force` (`-f`) to stage those files:

```bash
# If this fails due to gitignored files:
commit.sh -m "Add design doc" docs/spec.md

# Retry with --force:
commit.sh --force -m "Add design doc" docs/spec.md
```
```

- [ ] **Step 3: Provision to deploy updated files**

Run: `bin/provision`

This deploys the updated `commit.sh` and `SKILL.md` files to `~/.claude/skills/`, `~/.codex/skills/`, and `~/.gsd/agent/skills/`.

- [ ] **Step 4: Verify deployed commit.sh has the --force flag**

Run: `grep -c 'force' ~/.claude/skills/committing-changes/commit.sh`

Expected: A count >= 5 (multiple references to force in the updated script).

- [ ] **Step 5: Run tests one final time against deployed script**

Run: `COMMIT_SH=~/.claude/skills/committing-changes/commit.sh tmp/test-commit-sh.sh`

Wait — the test script hardcodes the path. Just re-run `tmp/test-commit-sh.sh` to test the repo source (already verified), then do a quick manual smoke test against the deployed version:

```bash
cd /tmp && mkdir -p force-test && cd force-test && git init -q && git config user.email "t@t" && git config user.name "T" && echo init > f && git add f && git commit -q -m i && echo "ignored/" > .gitignore && git add .gitignore && git commit -q -m gi && mkdir ignored && echo x > ignored/f.txt && ~/.claude/skills/committing-changes/commit.sh -m "should fail" ignored/f.txt 2>&1; echo "exit: $?" && ~/.claude/skills/committing-changes/commit.sh --force -m "should work" ignored/f.txt 2>&1; echo "exit: $?" && cd - && rm -rf /tmp/force-test
```

Expected: First command exits 1 with the gitignore error message. Second command exits 0 (or 1 from push-fail, but the commit is created — verify with `git log`).

- [ ] **Step 6: Commit**

```bash
~/.claude/skills/committing-changes/commit.sh -m "Document --force flag in commit skill SKILL.md files" roles/common/files/config/skills/common/committing-changes/SKILL.md roles/common/files/config/skills/gsd/committing-changes/SKILL.md
```

- [ ] **Step 7: Clean up test script**

```bash
rm tmp/test-commit-sh.sh
```
