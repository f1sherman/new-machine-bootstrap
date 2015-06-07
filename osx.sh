#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

# VARIABLES

instructions=""

# END VARIABLES

# FUNCTIONS

function run_with_progress {
  echo -e "${1}...\n"
  eval ${2}
  echo -e "\n${1} Complete!\n"
}

function install_if_no_binary {
  if ! command -v ${2} >/dev/null 2>&1; then
    run_with_progress "Installing ${1}" "${3}"
  fi
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

# BINARIES

install_if_no_binary Homebrew brew 'ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"'

# END BINARIES

# HOMEBREW UPDATE

run_with_progress "Updating Homebrew" "brew update"

# END HOMEBREW UPDATE

# HOMEBREW UPGRADE

run_with_progress "Upgrading Homebrew" "brew upgrade"

# END HOMEBREW UPGRADE

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
