#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: sync-and-install.sh [codespace]

Copies the current repository into the target Codespace's dotfiles directory
and runs the install script remotely.

Arguments:
  [codespace]   Name or ID of the Codespace (see `gh codespace list`). If omitted,
                an interactive fzf selection prompt is shown (requires fzf).

Requirements:
  - gh (GitHub CLI)
  - git
  - jq (for JSON parsing)
  - fzf (for interactive selection, optional)

Note:
  The dotfiles are synced to /workspaces/.codespaces/.persistedshare/dotfiles
  which is where GitHub Codespaces places dotfiles repositories.
USAGE
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Error: required command "%s" not found in PATH\n' "$1" >&2
    exit 1
  fi
}

require_command gh
require_command git
require_command jq

REMOTE_DIR='/workspaces/.codespaces/.persistedshare/dotfiles'

select_codespace() {
  if ! command -v fzf >/dev/null 2>&1; then
    printf 'fzf is required for interactive selection. Falling back to manual entry.\n' >&2
    gh codespace list
    printf 'Enter Codespace name: ' >&2
    read -r manual_name
    printf '%s\n' "$manual_name"
    return
  fi

  local json selection
  if ! json=$(gh codespace list --limit 50 --json name,displayName,repository); then
    printf 'Failed to list Codespaces. Ensure you are authenticated with gh.\n' >&2
    exit 1
  fi

  if [ -z "$json" ] || [ "$json" = "[]" ]; then
    printf 'No active Codespaces found.\n' >&2
    exit 1
  fi

  selection=$(printf '%s' "$json" | \
    jq -r '.[] | [.name, (.displayName // .name), (.repository // "")] | @tsv' | \
    fzf --delimiter='\t' \
        --with-nth=2,3 \
        --prompt='Select Codespace: ' \
        --height=40% \
        --border \
        --header='↑↓ navigate • Enter select • Esc cancel' \
        --preview='echo "Name: {1}\nDisplay: {2}\nRepository: {3}"' \
        --preview-window=up:3:wrap | \
    cut -f1
  ) || {
    printf 'No Codespace selected.\n' >&2
    exit 1
  }

  printf '%s\n' "$selection"
}

case $# in
  0)
    CODESPACE="$(select_codespace)"
    ;;
  1)
    CODESPACE="$1"
    ;;
  *)
    printf 'Error: Too many arguments\n' >&2
    usage
    exit 1
    ;;
esac

if [ -z "$CODESPACE" ]; then
  printf 'No Codespace selected.\n' >&2
  exit 1
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"

printf '[sync] Updating Codespace %s at %s\n' "$CODESPACE" "$REMOTE_DIR"

# Use tar to pipe files through ssh (more reliable than gh codespace cp)
printf '[sync] Syncing files via tar\n'
(cd "${REPO_ROOT}" && tar --disable-copyfile -czf - .) | \
  gh codespace ssh -c "$CODESPACE" -- "mkdir -p ${REMOTE_DIR} && cd ${REMOTE_DIR} && tar --warning=no-unknown-keyword -xzf -"

REMOTE_INSTALL="${REMOTE_DIR}/install.sh"

printf '[sync] Running install script\n'
gh codespace ssh -c "$CODESPACE" -- "bash ${REMOTE_INSTALL}"

printf '[sync] Codespace %s provisioning complete\n' "$CODESPACE"
