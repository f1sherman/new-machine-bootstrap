#!/usr/bin/env bash
# shellcheck shell=bash

# Lightweight logging helpers
log_info() {
  printf '[codespaces] %s\n' "$*" >&2
}

log_warn() {
  printf '[codespaces][warn] %s\n' "$*" >&2
}

# Check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Require a command to exist, otherwise exit with message
require_command() {
  if ! command_exists "$1"; then
    log_warn "Required command '$1' not found in PATH"
    return 1
  fi
}

# Ensure parent directory exists for a path
ensure_parent_dir() {
  local target=$1
  mkdir -p "$(dirname "$target")"
}

# Backup an existing file or symlink before replacing it
backup_file() {
  local path=$1
  local timestamp
  timestamp=$(date +%Y%m%d%H%M%S)
  local backup="${path}.bak.${timestamp}"
  mv "$path" "$backup"
  log_info "Backed up ${path} -> ${backup}"
}

# Create or update a symlink, backing up conflicting files
link_file() {
  local source=$1
  local target=$2

  ensure_parent_dir "$target"

  if [ -L "$target" ]; then
    local current
    current=$(readlink "$target")
    if [ "$current" = "$source" ]; then
      return 0
    fi
  elif [ -e "$target" ]; then
    backup_file "$target"
  fi

  ln -sfn "$source" "$target"
  log_info "Linked ${target} -> ${source}"
}

# Install (copy) a file with the provided mode, backing up existing files first
install_file() {
  local source=$1
  local target=$2
  local mode=${3:-0644}

  ensure_parent_dir "$target"

  if [ -e "$target" ] || [ -L "$target" ]; then
    if cmp -s "$source" "$target" 2>/dev/null; then
      chmod "$mode" "$target"
      return 0
    fi
    backup_file "$target"
  fi

  install -m "$mode" "$source" "$target"
  log_info "Installed ${target} (mode ${mode})"
}
