#!/bin/bash
set -euo pipefail
export GIT_AUTHOR_NAME=worker GIT_COMMITTER_NAME=worker
export GIT_AUTHOR_EMAIL=worker@example.invalid
export GIT_COMMITTER_EMAIL=worker@example.invalid
export GIT_AUTHOR_DATE=2000-01-01T00:00:00Z
export GIT_COMMITTER_DATE=2000-01-01T00:00:00Z
mkdir -p /workspace/project
cd /workspace/project
git init -q -b main
git init -q --bare /workspace/remote.git
git remote add origin /workspace/remote.git
printf '.worktrees/\n' > .gitignore
printf 'use_worktrees: true\n' > .repo.yml
git add .
git commit -qm fixture
git push -qu origin main
git worktree add -qb fix/abandoned .worktrees/abandoned
cd .worktrees/abandoned
printf 'unique unpublished work\n' > unique.txt
git add unique.txt
git commit -qm 'unpublished work'
