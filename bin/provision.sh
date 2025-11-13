#!/bin/bash
set -e

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

install_ansible() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "Installing Ansible via Homebrew..."
    brew install ansible || { echo "Failed to install Ansible"; exit 1; }
  elif command_exists apt-get; then
    echo "Installing Ansible via apt..."
    sudo apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ansible || { echo "Failed to install Ansible"; exit 1; }
  else
    echo "Unsupported platform for automatic Ansible installation"
    exit 1
  fi
}

in_codespaces() {
  [[ "$CODESPACES" == "true" ]]
}

if ! command_exists ansible-playbook; then
  install_ansible
fi

if in_codespaces; then
  ansible-playbook \
    --inventory localhost, \
    --connection local \
    playbook.yml \
    --diff \
    "$@"
else
  ansible-playbook \
    --ask-become-pass \
    --inventory localhost, \
    --connection local \
    playbook.yml \
    --diff \
    "$@"
fi
