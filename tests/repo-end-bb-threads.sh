#!/usr/bin/env bash
set -euo pipefail

unset TMUX TMUX_PANE BB_THREAD_ID BB_ENVIRONMENT_ID REPO_END_SKIP_BB_THREAD_CHECK

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_END_SCRIPT="$(cd "$SCRIPT_DIR/../roles/common/files/bin" && pwd)/repo-end"

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

export GIT_AI_SKIP_ALL_HOOKS=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com

fail() {
  printf 'FAIL  %s\n' "$1" >&2
  exit 1
}

fake_bin="$TMPROOT/bin"
mkdir -p "$fake_bin"
cat >"$fake_bin/bb" <<'EOF'
#!/usr/bin/env bash
[[ "$*" == "thread list --include-hidden --json" ]] || exit 64
[[ "${BB_FIXTURE_FAIL:-}" != "1" ]] || exit 1
cat "$BB_FIXTURE_THREADS"
EOF
chmod +x "$fake_bin/bb"

# Builds a merged feature branch in its own worktree. Sets WORKTREE.
make_merged_worktree() {
  local name="$1" origin repo
  origin="$TMPROOT/$name-origin.git"
  repo="$(realpath "$(mktemp -d "$TMPROOT/$name-repo.XXXXXX")")"
  git init -q --bare "$origin"
  git init -qb main "$repo"
  git -C "$repo" remote add origin "$origin"
  git -C "$repo" commit -q --allow-empty -m init
  git -C "$repo" push -q -u origin main
  WORKTREE="$repo-feature"
  git -C "$repo" worktree add -q -b feature "$WORKTREE" main
  git -C "$WORKTREE" commit -q --allow-empty -m work
  git -C "$WORKTREE" push -q -u origin feature
  git -C "$repo" merge --ff-only --quiet feature
  git -C "$repo" push -q origin main
  WORKTREE="$(realpath "$WORKTREE")"
}

run_repo_end() {
  (cd "$WORKTREE" && HOME="$TMPROOT/home" PATH="$fake_bin:$PATH" \
    BB_FIXTURE_THREADS="$TMPROOT/threads.json" "$REPO_END_SCRIPT")
}

mkdir -p "$TMPROOT/home"

make_merged_worktree live
printf '[{"id":"thr_other","title":"Command center","archivedAt":null,"environmentPath":"%s"}]\n' \
  "$WORKTREE" >"$TMPROOT/threads.json"
if run_repo_end >"$TMPROOT/out" 2>"$TMPROOT/err"; then
  fail "repo-end removed a worktree that an unarchived thread uses"
fi
[[ -d "$WORKTREE" ]] || fail "refused cleanup still removed the worktree"
grep -q 'thr_other' "$TMPROOT/err" || fail "refusal does not name the thread"
printf 'ok  unarchived thread blocks cleanup\n'

ln -s "$WORKTREE" "$TMPROOT/linked-path"
printf '[{"id":"thr_other","title":"Linked","archivedAt":null,"environmentPath":"%s"}]\n' \
  "$TMPROOT/linked-path" >"$TMPROOT/threads.json"
if run_repo_end >"$TMPROOT/out" 2>"$TMPROOT/err"; then
  fail "repo-end removed a worktree that a thread reaches through a symlink"
fi
[[ -d "$WORKTREE" ]] || fail "symlink refusal still removed the worktree"
printf 'ok  symlinked thread path blocks cleanup\n'

printf '[{"id":"thr_other","title":"Old","archivedAt":1,"environmentPath":"%s"}]\n' \
  "$WORKTREE" >"$TMPROOT/threads.json"
run_repo_end >"$TMPROOT/out" 2>"$TMPROOT/err" ||
  fail "archived thread blocked cleanup: $(<"$TMPROOT/err")"
[[ ! -d "$WORKTREE" ]] || fail "cleanup left the worktree behind"
printf 'ok  archived thread does not block cleanup\n'

make_merged_worktree lookup-failure
printf '[]\n' >"$TMPROOT/threads.json"
if (cd "$WORKTREE" && BB_FIXTURE_FAIL=1 HOME="$TMPROOT/home" \
  PATH="$fake_bin:$PATH" BB_FIXTURE_THREADS="$TMPROOT/threads.json" \
  "$REPO_END_SCRIPT") >/dev/null 2>&1; then
  fail "repo-end proceeded after the BB thread lookup failed"
fi
[[ -d "$WORKTREE" ]] || fail "failed lookup still removed the worktree"
printf 'ok  failed lookup blocks cleanup\n'

printf '[{"id":"thr_other","title":"Live","archivedAt":null,"environmentPath":"%s"}]\n' \
  "$WORKTREE" >"$TMPROOT/threads.json"
(cd "$WORKTREE" && REPO_END_SKIP_BB_THREAD_CHECK=1 HOME="$TMPROOT/home" \
  PATH="$fake_bin:$PATH" BB_FIXTURE_THREADS="$TMPROOT/threads.json" \
  "$REPO_END_SCRIPT") >/dev/null 2>&1 || fail "skip variable did not bypass the check"
[[ ! -d "$WORKTREE" ]] || fail "skipped check left the worktree behind"
printf 'ok  skip variable bypasses the check\n'
