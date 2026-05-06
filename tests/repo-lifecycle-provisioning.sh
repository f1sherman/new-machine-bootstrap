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
require_contains roles/common/templates/dotfiles/gitignore '.worktrees/' 'global gitignore ignores default worktree root'
require_contains roles/common/tasks/main.yml 'repo-lib.sh' 'installs repo-lib'
require_contains roles/common/tasks/main.yml 'repo-start' 'installs repo-start'
require_contains roles/common/tasks/main.yml 'repo-end' 'installs repo-end'
require_contains roles/common/tasks/main.yml 'cleanup-branches' 'installs cleanup-branches from common role'
require_contains roles/common/tasks/main.yml 'Remove legacy public worktree helpers' 'removes legacy worktree helpers'
require_contains roles/common/tasks/main.yml 'worktree-start' 'legacy cleanup names worktree-start'
require_contains roles/common/tasks/main.yml 'worktree-lib.sh' 'legacy cleanup names worktree-lib'
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
require_contains roles/common/files/claude/CLAUDE.md.d/00-base.md 'repo-start' 'Claude base instructions name repo-start'
require_not_contains roles/common/files/claude/CLAUDE.md.d/00-base.md 'worktree-start' 'Claude base instructions stop naming worktree-start'
require_contains roles/common/files/claude/hooks/block-main-branch-edits.sh 'repo-start <branch>' 'Claude main edit hook names repo-start'
require_contains roles/common/files/claude/hooks/block-worktree-commands.sh 'Use repo-start instead.' 'Claude raw worktree add hook names repo-start'
require_contains roles/common/files/claude/hooks/block-worktree-commands.sh 'cleanup-branches --branch <branch>' 'Claude raw worktree remove hook names cleanup script'
require_not_contains roles/common/files/claude/hooks/block-worktree-commands.sh 'worktree-start' 'Claude raw worktree hook stops naming worktree-start'
require_contains roles/common/files/share/skills/_pr-workflow-common/agent-worktree-path.sh 'repo-start <branch>' 'PR workflow worktree recovery names repo-start'
require_not_contains roles/common/files/share/skills/_pr-workflow-common/agent-worktree-path.sh 'worktree-start' 'PR workflow worktree recovery stops naming worktree-start'
require_contains roles/common/files/share/skills/_pr-workflow-common/agent-worktree-path.sh 'non-main named branch' 'PR workflow allows branch lifecycle paths'
require_not_contains roles/common/files/share/skills/_pr-workflow-common/agent-worktree-path.sh 'not a linked git worktree' 'PR workflow stops requiring linked worktrees'
require_contains roles/common/tasks/main.yml 'block-initiation-skill-on-main.sh' \
  'main.yml registers initiation-skill PostToolUse hook'
require_contains roles/common/tasks/main.yml 'PostToolUse' \
  'main.yml mentions PostToolUse event'
require_contains roles/common/files/claude/hooks/block-initiation-skill-on-main.sh 'repo-start' \
  'initiation-skill hook names repo-start'

printf 'PASS  repo lifecycle provisioning checks\n'
