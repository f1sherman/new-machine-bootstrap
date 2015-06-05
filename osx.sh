#!/usr/bin/env bash

function install_if_not_exists {
  if ! command -v $2 >/dev/null 2>&1; then
    echo "Installing $1"
    echo $3
    eval $3
  fi
}

install_if_not_exists Homebrew brew 'ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"'
