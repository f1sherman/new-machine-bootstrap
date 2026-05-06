#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"

require_contains() {
  local file="$1" needle="$2" name="$3"
  grep -Fq -- "$needle" "$ROOT/$file" || {
    printf 'FAIL  %s\n' "$name" >&2
    exit 1
  }
  printf 'PASS  %s\n' "$name"
}

require_not_contains() {
  local file="$1" needle="$2" name="$3"
  ! grep -Fq -- "$needle" "$ROOT/$file" || {
    printf 'FAIL  %s\n' "$name" >&2
    exit 1
  }
  printf 'PASS  %s\n' "$name"
}

require_contains roles/common/templates/dotfiles/gitignore '.repo.yml' 'global gitignore ignores .repo.yml'
require_contains roles/common/tasks/main.yml 'repo-lib.sh' 'installs repo-lib'
require_contains roles/common/tasks/main.yml 'repo-start' 'installs repo-start'
require_contains roles/common/tasks/main.yml 'repo-end' 'installs repo-end'
require_contains roles/common/tasks/main.yml 'cleanup-branches' 'installs cleanup-branches from common role'
require_not_contains roles/common/templates/dotfiles/zshrc.d/50-personal-dev-shell.zsh 'worktree-start()' 'zsh removes worktree-start wrapper'
require_not_contains roles/common/templates/dotfiles/zshrc.d/50-personal-dev-shell.zsh 'wts()' 'zsh removes wts wrapper'
require_contains roles/common/templates/dotfiles/zshrc.d/50-personal-dev-shell.zsh 'repo-start()' 'zsh exposes repo-start wrapper'
require_contains roles/common/templates/dotfiles/zshrc.d/50-personal-dev-shell.zsh 'rs()' 'zsh exposes rs wrapper'
require_contains roles/common/templates/dotfiles/zshrc.d/50-personal-dev-shell.zsh 'repo-end()' 'zsh exposes repo-end wrapper'
require_contains roles/common/templates/dotfiles/zshrc.d/50-personal-dev-shell.zsh 're()' 'zsh exposes re wrapper'
require_contains roles/macos/templates/dotfiles/bash_profile 'repo-start()' 'bash exposes repo-start wrapper'
require_contains roles/macos/templates/dotfiles/bash_profile 'repo-end()' 'bash exposes repo-end wrapper'
require_contains roles/common/files/bin/codex-block-main-branch-edits 'repo-start <branch>' 'main edit hook names repo-start'
require_contains roles/common/files/bin/codex-block-worktree-commands 'Use repo-start instead.' 'raw worktree add hook names repo-start'
require_contains roles/common/files/bin/codex-block-worktree-commands 'cleanup-branches --branch <branch>' 'raw worktree remove hook names cleanup script'
require_not_contains roles/common/files/bin/codex-block-worktree-commands 'worktree-start' 'raw worktree hook stops naming worktree-start'

printf 'PASS  repo lifecycle provisioning checks\n'
