#!/usr/bin/env bash

instructions=""

function install_if_not_exists {
  if ! command -v $2 >/dev/null 2>&1; then
    echo -e "Installing $1...\n"
    eval $3
    echo -e "\n$1 Installation Complete!\n"
  fi
}

function add_instruction {
  instructions="$instructions\n$1"
}

install_if_not_exists Homebrew brew 'ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"'

if [ "$(fdesetup status)" != "FileVault is On." ]; then
  add_instruction 'Setup FileVault'
fi

if [ "$instructions" != "" ]; then
  echo -e ""
  echo -e "---------------------------------"
  echo -e "| Stuff you need to do manually |"
  echo -e "---------------------------------"
  echo -e "$instructions"
  echo -e ""
fi
