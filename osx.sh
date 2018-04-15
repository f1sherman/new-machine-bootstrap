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
