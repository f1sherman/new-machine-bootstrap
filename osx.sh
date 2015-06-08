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

function run_with_progress {
  log_start "${1}"
  eval ${2}
  log_end "${1}"
}

function brew_if_not_brewed {
  if ! brew list ${1} >/dev/null 2>&1; then
    run_with_progress "Brewing ${1}" "brew install ${1}"
  fi
}

function add_instruction {
  instructions="${instructions}\n${1}"
}

# END FUNCTIONS

# INSTALL/UPDATE HOMEBREW

if is_binary_installed brew; then
  run_with_progress "Updating Homebrew" "brew update"
  run_with_progress "Upgrading Homebrew" "brew upgrade"
else
  run_with_progress "Installing Homebrew" 'ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"'
fi

# END INSTALL/UPDATE HOMEBREW

# BREW RECIPES

brew_if_not_brewed curl
brew_if_not_brewed git
brew_if_not_brewed nmap
brew_if_not_brewed node
brew_if_not_brewed ssh-copy-id
brew_if_not_brewed tmux
brew_if_not_brewed vim
brew_if_not_brewed wget

# END BREW RECIPES

# GENERATE SSH KEY

if [ ! -e ~/.ssh/id_rsa.pub ]; then
  log_start "Generating an SSH Key"
  echo -n "Enter SSH Passphrase:"
  read -s ssh_passphrase
  echo

  ssh-keygen -N "${ssh_passphrase}" -f ~/.ssh/id_rsa
  echo -e "\nYour SSH key has been generated. Add the below public key to github and press any key to continue when finished..."
  echo "$(cat ~/.ssh/id_rsa.pub)"
  read -n 1 -s
  echo
  log_end "Generating an SSH Key"
fi

# END GENERATE SSH KEY

# SETUP VIM

if [ ! -d ~/.vim ]; then
  log_start "Setting up vim"
  git clone git@github.com:f1sherman/dotvim.git ~/.vim
  cd ~/.vim
  ln -s ~/.vim/vimrc ~/.vimrc
  ln -s ~/.vim/gvimrc ~/.gvimrc
  mkdir ~/.vimtmp
  git clone https://github.com/gmarik/Vundle.vim.git ~/.vim/bundle/Vundle.vim
  vim +PluginInstall +qall
  cd -
  log_end "Setting up vim"
else
  log_start "Updating vim plugins"
  cd ~/.vim
  git pull origin master
  vim +PluginInstall! +qall
  cd -
  log_end "Updating vim plugins"
fi

# END SETUP VIM

# SETUP DOTFILES

if [ -d ~/projects ]; then
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

source ~/.bash_profile

# END SETUP DOTFILES

# SET OS X DEFAULTS

log_start "Setting OS X defaults"

~/projects/dotfiles/osx/set_defaults.sh

log_end "Setting OS X defaults"

# END SET OS X DEFAULTS

# ADD MANUAL INSTRUCTIONS

if [ "$(fdesetup status)" != "FileVault is On." ]; then
  add_instruction 'Setup FileVault'
fi

# END ADD MANUAL INSTRUCTIONS

# PRINT MANUAL INSTRUCTIONS

if [ "${instructions}" != "" ]; then
  echo -e ""
  echo -e "---------------------------------"
  echo -e "| Stuff you need to do manually |"
  echo -e "---------------------------------"
  echo -e "${instructions}"
  echo -e ""
fi

# END PRINT MANUAL INSTRUCTIONS
