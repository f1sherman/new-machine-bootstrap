#!/usr/bin/env bash
set -euo pipefail

original_command="${1:-}"
pane_dir="${2:-}"

case "$original_command" in
  nvim) argument='' ;;
  nvim\ *) argument=${original_command#nvim } ;;
  *) printf '%s\n' "$original_command"; exit 0 ;;
esac

if [ -f "$pane_dir/Session.vim" ]; then
  printf '%s\n' 'nvim -S'
  exit 0
fi

case "$argument" in
  -S*) printf '%s\n' 'nvim'; exit 0 ;;
  '') printf '%s\n' 'nvim'; exit 0 ;;
  -*) printf '%s\n' "$original_command"; exit 0 ;;
esac

if [[ "$argument" = /* ]]; then
  candidate="$argument"
else
  candidate="$pane_dir/$argument"
fi

if [ -f "$candidate" ] || [ -d "$candidate" ]; then
  printf 'nvim %q\n' "$argument"
else
  printf '%s\n' "$original_command"
fi
