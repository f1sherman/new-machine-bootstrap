#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

# VARIABLES

instructions=""

# END VARIABLES

# FUNCTIONS

function is_binary_installed {
  if ! command -v ${1} >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

function run_with_progress {
  echo -e "${1}...\n"
  eval ${2}
  echo -e "\n${1} Complete!\n"
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
  run_with_progress "Installing Homebrew" 'ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"'
else
  run_with_progress "Updating Homebrew" "brew update"
  run_with_progress "Upgrading Homebrew" "brew upgrade"
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
  echo -e "\nGenerating an SSH Key"
  echo -n "Enter SSH Passphrase:"
  read -s ssh_passphrase
  echo

  ssh-keygen -N "${ssh_passphrase}" -f ~/.ssh/id_rsa
  echo -e "\nYour SSH key has been generated. Add the below public key to github and press any key to continue when finished..."
  echo "$(cat ~/.ssh/id_rsa.pub)"
  read -n 1 -s
  echo
fi

# END GENERATE SSH KEY

# SETUP VIM

if [ ! -d ~/.vim ]; then
  echo -e "Setting up vim...\n"
  git clone git@github.com:f1sherman/dotvim.git ~/.vim
  cd ~/.vim
  ln -s ~/.vim/vimrc ~/.vimrc
  ln -s ~/.vim/gvimrc ~/.gvimrc
  mkdir ~/.vimtmp
  git clone https://github.com/gmarik/Vundle.vim.git ~/.vim/bundle/Vundle.vim
  vim +BundleInstall +qall
  echo -e "\nvim setup complete!\n"
else
  echo -e "Updating vim plugins...\n"
  cd ~/.vim
  git pull origin master
  vim +PluginInstall! +qall
  echo -e "\nvim plugin update complete!\n"
fi

# END SETUP VIM

# SETUP DOTFILES

#if [ ! -d "~/projects" ]; then
  #mkdir ~/projects
  #cd ~/projects
#fi

# END SETUP DOTFILES

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
