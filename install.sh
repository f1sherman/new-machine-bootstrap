#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}"
UTILS="${REPO_ROOT}/codespaces/bootstrap/lib/utils.sh"

if [ ! -f "$UTILS" ]; then
  echo "[codespaces] Utility library missing at ${UTILS}" >&2
  exit 1
fi

# shellcheck source=codespaces/bootstrap/lib/utils.sh
. "$UTILS"

APT_PACKAGES=(
  bat
  byobu
  curl
  fd-find
  fzf
  git
  neovim
  python3
  python3-pip
  python3-venv
  pipx
  ripgrep
  sudo
  tmux
  unzip
  zsh
)

ensure_prerequisites() {
  require_command sudo || {
    log_warn "sudo is required to install packages"
    exit 1
  }
  require_command git || {
    log_warn "git is required to clone supporting repositories"
    exit 1
  }
  if ! command_exists apt-get; then
    log_warn "apt-get is required for package installation on Codespaces/Linux"
    exit 1
  fi
}

install_packages() {
  log_info "Updating apt package index"
  sudo apt-get update
  log_info "Installing packages: ${APT_PACKAGES[*]}"
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${APT_PACKAGES[@]}"
}

ensure_tool_aliases() {
  mkdir -p "${HOME}/.local/bin"

  if ! command_exists fd && command_exists fdfind; then
    ln -sfn "$(command -v fdfind)" "${HOME}/.local/bin/fd"
    log_info "Created fd alias pointing to fdfind"
  fi

  if ! command_exists bat && command_exists batcat; then
    ln -sfn "$(command -v batcat)" "${HOME}/.local/bin/bat"
    log_info "Created bat alias pointing to batcat"
  fi
}

sync_prezto() {
  local prezto_dir="${HOME}/.zprezto"
  if [ -d "${prezto_dir}/.git" ]; then
    log_info "Updating existing Prezto installation"
    git -C "$prezto_dir" pull --ff-only
    git -C "$prezto_dir" submodule update --init --recursive
  else
    log_info "Cloning Prezto"
    git clone --recursive https://github.com/sorin-ionescu/prezto.git "$prezto_dir"
  fi
}

sync_dotvim() {
  local vim_dir="${HOME}/.vim"
  if [ -d "${vim_dir}/.git" ]; then
    log_info "Updating dotvim configuration"
    if ! git -C "$vim_dir" pull --ff-only; then
      log_warn "Failed to update dotvim repository; continuing with existing version"
    fi
  else
    log_info "Cloning dotvim configuration"
    if ! git clone https://github.com/f1sherman/dotvim.git "$vim_dir"; then
      log_warn "Unable to clone dotvim repository; Vim/Neovim configuration will be limited"
    fi
  fi
}

link_dotfiles() {
  local dotfiles_root="${REPO_ROOT}/roles/macos/templates/dotfiles"

  link_file "${dotfiles_root}/zshenv" "${HOME}/.zshenv"
  link_file "${dotfiles_root}/zshrc" "${HOME}/.zshrc"
  link_file "${dotfiles_root}/zlogin" "${HOME}/.zlogin"
  link_file "${dotfiles_root}/zpreztorc" "${HOME}/.zpreztorc"
  link_file "${dotfiles_root}/tmux.conf" "${HOME}/.tmux.conf"

  mkdir -p "${HOME}/.byobu"
  link_file "${dotfiles_root}/tmux.conf" "${HOME}/.byobu/.tmux.conf"

  mkdir -p "${HOME}/.config/nvim"
  if [ -f "${HOME}/.vim/vimrc" ]; then
    link_file "${HOME}/.vim/vimrc" "${HOME}/.config/nvim/init.vim"
    link_file "${HOME}/.vim/vimrc" "${HOME}/.vimrc"
  else
    log_warn "dotvim repository missing; skipping Vim/Neovim symlinks"
  fi
}

install_helpers() {
  local scripts_root="${REPO_ROOT}/roles/macos"

  install_file "${REPO_ROOT}/roles/macos/templates/pick-files" "${HOME}/bin/pick-files" 0755
  install_file "${scripts_root}/files/bin/osc52-copy" "${HOME}/bin/osc52-copy" 0755

  ensure_tool_aliases
}

enable_byobu() {
  if grep -q 'byobu-launch' "${HOME}/.bashrc" 2>/dev/null; then
    log_info "Byobu already enabled"
    return
  fi

  log_info "Enabling Byobu auto-launch"

  # Try using byobu-enable first
  if command_exists byobu-enable; then
    if byobu-enable 2>&1 | grep -q "Byobu"; then
      log_info "Byobu enabled successfully"
      return
    fi
  fi

  # Fallback: manually add byobu-launch to .bashrc
  if command_exists byobu-launch; then
    log_info "Manually adding byobu-launch to .bashrc"
    cat >> "${HOME}/.bashrc" <<'BYOBU'

# Added by dotfiles installer
_byobu_sourced=1 . /usr/bin/byobu-launch 2>/dev/null || true
BYOBU
    log_info "Byobu auto-launch configured"
  else
    log_warn "byobu-launch command not found; skipping auto-start configuration"
  fi
}

finalize_environment() {
  if command_exists pipx; then
    pipx ensurepath >/dev/null 2>&1 || true
  fi
}

main() {
  log_info "Starting Codespaces bootstrap"

  ensure_prerequisites
  install_packages
  sync_prezto
  sync_dotvim
  link_dotfiles
  install_helpers
  enable_byobu
  finalize_environment

  log_info "Bootstrap complete. Open a new shell to begin using the environment."
}

main "$@"
