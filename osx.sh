#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

# FUNCTIONS

function log_start {
  echo -e "${1}...\n"
}

function log_end {
  echo -e "\n${1} Complete!\n"
}

function run_with_progress {
  log_start "${1}"
  eval ${2}
  log_end "${1}"
}

function is_binary_installed {
  if command -v ${1} >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

# END FUNCTIONS

# INITIALIZE SUDO

sudo -v

# END INITIALIZE SUDO

# Run ruby install script

run_with_progress "Running ruby install script", 'ruby <(curl -fsSL https://raw.githubusercontent.com/f1sherman/new-machine-bootstrap/master/macos)'

# End ruby install script

# SETUP DOTFILES

if [[ -d ~/projects ]]; then
  log_start "Updating dotfiles"
  cd ~/projects/dotfiles
  git pull origin master
  cd -
  log_end "Updating dotfiles"
else
  log_start "Setting up dotfiles"
  mkdir ~/projects
  git clone git@github.com:f1sherman/dotfiles.git ~/projects/dotfiles
  cd ~/projects/dotfiles
  rake install
  cd -
  log_end "Setting up dotfiles"
fi

# END SETUP DOTFILES

# SETUP FZF

log_start "Installing FZF"

set +u # FZF references undefined variables
source ~/.bash_profile
set -o nounset

/usr/local/opt/fzf/install --all

log_end "Installing FZF"

# END SETUP FZF

# SET OS X DEFAULTS

log_start "Setting OS X defaults"

~/projects/dotfiles/osx/set_defaults.sh

log_end "Setting OS X defaults"

# END SET OS X DEFAULTS

# ENABLE DARK MODE

dark-mode on

# END ENABLE DARK MODE
