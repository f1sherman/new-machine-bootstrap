#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

# VARIABLES

instructions=""

# END VARIABLES

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

function add_instruction {
  instructions="${instructions}\n${1}"
}

# END FUNCTIONS

# INITIALIZE SUDO

sudo -v

# END INITIALIZE SUDO

# Run ruby install script

run_with_progress "Running ruby install script", 'ruby <(curl -fsSL https://raw.githubusercontent.com/f1sherman/new-machine-bootstrap/master/macos)'

# End ruby install script

# SETUP VIM

if [[ ! -d ~/.vim ]]; then
  log_start "Setting up vim"
  git clone git@github.com:f1sherman/dotvim.git ~/.vim
  cd ~/.vim
  ln -s ~/.vim/vimrc ~/.vimrc
  ln -s ~/.vim/gvimrc ~/.gvimrc
  mkdir ~/.vimtmp
  vim +qall
  cd -
  log_end "Setting up vim"
fi

log_start "Updating vim plugins"
cd ~/.vim
git pull origin master
vim +PlugUpdate +qall
vim +PlugUpgrade +qall
vim +PlugClean +qall
~/.vim/plugged/YouCompleteMe/install.py
cd -
log_end "Updating vim plugins"

# END SETUP VIM

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

dark-mode --mode Dark

# END ENABLE DARK MODE

# PRINT MANUAL INSTRUCTIONS

if [[ "${instructions}" != "" ]]; then
  echo -e ""
  echo -e "---------------------------------"
  echo -e "| Stuff you need to do manually |"
  echo -e "---------------------------------"
  echo -e "${instructions}"
  echo -e ""
fi

# END PRINT MANUAL INSTRUCTIONS
