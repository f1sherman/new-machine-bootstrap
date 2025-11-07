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
      return
    fi
  fi

  if [ -f "${vim_dir}/vimrc" ]; then
    log_info "Installing vim plugins"
    vim -u "${vim_dir}/vimrc" +PlugInstall +qall > /dev/null 2>&1 || log_warn "Failed to install vim plugins"
  fi
}

link_dotfiles() {
  local dotfiles_root="${REPO_ROOT}/roles/macos/templates/dotfiles"
  local codespaces_dotfiles="${REPO_ROOT}/codespaces/dotfiles"

  link_file "${dotfiles_root}/zshenv" "${HOME}/.zshenv"
  link_file "${dotfiles_root}/zshrc" "${HOME}/.zshrc"
  link_file "${dotfiles_root}/zlogin" "${HOME}/.zlogin"
  link_file "${dotfiles_root}/zpreztorc" "${HOME}/.zpreztorc"

  link_file "${codespaces_dotfiles}/tmux.conf" "${HOME}/.tmux.conf"

  mkdir -p "${HOME}/.byobu"
  link_file "${codespaces_dotfiles}/tmux.conf" "${HOME}/.byobu/.tmux.conf"

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
  log_info "Enabling Byobu auto-launch"

  if ! command_exists byobu; then
    log_warn "byobu command not found; skipping auto-start configuration"
    return
  fi

  # Change default shell to zsh
  if [ "$SHELL" != "$(command -v zsh)" ]; then
    log_info "Changing default shell to zsh"
    sudo chsh -s "$(command -v zsh)" "$(whoami)" || log_warn "Failed to change shell to zsh"
  fi

  # Add byobu launch to TOP of .bashrc (before mise activates)
  if ! grep -q 'BYOBU_SESSION' "${HOME}/.bashrc" 2>/dev/null; then
    log_info "Adding byobu auto-launch to .bashrc (at top)"
    {
      cat <<'BYOBU_BASH'
# Added by dotfiles installer - launch byobu with unique session per connection
# Must be at top before mise/other tools activate
if [ -z "$TMUX" ]; then
  exec byobu new-session -A -s "codespace-$$"
fi

BYOBU_BASH
      cat "${HOME}/.bashrc"
    } > "${HOME}/.bashrc.tmp"
    mv "${HOME}/.bashrc.tmp" "${HOME}/.bashrc"
  fi

  # Add byobu launch to .zshrc.local (for subsequent logins once chsh takes effect)
  local zshrc_local="${HOME}/.zshrc.local"
  if ! grep -q 'BYOBU_SESSION' "$zshrc_local" 2>/dev/null; then
    log_info "Adding byobu auto-launch to .zshrc.local"
    cat >> "$zshrc_local" <<'BYOBU_ZSH'

# Added by dotfiles installer - launch byobu with unique session per connection
# Only launch if not already in a tmux/byobu session
if [ -z "$TMUX" ]; then
  BYOBU_SESSION="ssh-$(date +%s)-$$"
  byobu new-session -d -s "$BYOBU_SESSION" 2>/dev/null || true
  byobu attach-session -t "$BYOBU_SESSION" 2>/dev/null || true
fi
BYOBU_ZSH
    log_info "Byobu auto-launch configured"
  else
    log_info "Byobu already configured in .zshrc.local"
  fi
}

setup_claude() {
  log_info "Setting up Claude configuration"

  local claude_dir="${HOME}/.claude"
  mkdir -p "${claude_dir}/agents"
  mkdir -p "${claude_dir}/commands"

  local dotfiles_claude="${REPO_ROOT}/roles/macos/templates/dotfiles/claude"

  if [ -d "${dotfiles_claude}/agents" ]; then
    log_info "Copying Claude agents"
    cp -r "${dotfiles_claude}/agents/"* "${claude_dir}/agents/" 2>/dev/null || log_warn "No agents to copy"
  fi

  if [ -d "${dotfiles_claude}/commands" ]; then
    log_info "Copying Claude commands"
    cp -r "${dotfiles_claude}/commands/"* "${claude_dir}/commands/" 2>/dev/null || log_warn "No commands to copy"
  fi

  log_info "Creating ~/.claude/CLAUDE.md"
  cat > "${claude_dir}/CLAUDE.md" <<'CLAUDE_MD'
Add code comments sparingly. Focus on why something is done, especially for complex logic, rather than what is done. Only add high-value comments if necessary for clarity or if requested by the user. Do not edit comments that are separate from the code you are changing. NEVER talk to the user or describe your changes through comments.
CLAUDE_MD

  local ccstatusline_version="2.0.21"
  local ccstatusline_config="${REPO_ROOT}/roles/macos/files/config/ccstatusline/settings.json"
  local ccstatusline_dir="${HOME}/.config/ccstatusline"

  if [ -f "${ccstatusline_config}" ]; then
    log_info "Installing ccstatusline configuration"
    mkdir -p "${ccstatusline_dir}"
    cp "${ccstatusline_config}" "${ccstatusline_dir}/settings.json"
  fi

  log_info "Generating ~/.claude/settings.json"
  local settings_file="${claude_dir}/settings.json"

  if [ -f "${settings_file}" ]; then
    log_info "Merging ccstatusline into existing Claude settings"
    if command_exists python3; then
      python3 -c "
import json
import sys

try:
    with open('${settings_file}', 'r') as f:
        settings = json.load(f)
except:
    settings = {}

settings['statusLine'] = {
    'type': 'command',
    'command': 'npx -y ccstatusline@${ccstatusline_version}',
    'padding': 0
}

with open('${settings_file}', 'w') as f:
    json.dump(settings, f, indent=2)
" || log_warn "Failed to merge Claude settings"
    fi
  else
    log_info "Creating new Claude settings.json"
    cat > "${settings_file}" <<SETTINGS_JSON
{
  "statusLine": {
    "type": "command",
    "command": "npx -y ccstatusline@${ccstatusline_version}",
    "padding": 0
  }
}
SETTINGS_JSON
  fi

  chmod 0700 "${claude_dir}"
  chmod 0600 "${claude_dir}/CLAUDE.md" 2>/dev/null || true
  chmod 0600 "${settings_file}" 2>/dev/null || true
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
  setup_claude
  enable_byobu
  finalize_environment

  log_info "Bootstrap complete. Open a new shell to begin using the environment."
}

main "$@"
