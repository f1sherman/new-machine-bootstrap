#!/bin/bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

FAKE_BIN="$TMP_ROOT/bin"
mkdir -p "$FAKE_BIN"

cat > "$FAKE_BIN/sudo" <<'SCRIPT'
#!/bin/bash
set -e
while [[ "${1:-}" == *=* ]]; do
  export "$1"
  shift
done
exec "$@"
SCRIPT

cat > "$FAKE_BIN/apt-get" <<'SCRIPT'
#!/bin/bash
set -e
printf '%s\n' "$*" >> "$APT_CALLS"

apt_lists_lock_error() {
  if [[ "${LC_ALL:-}" == C ]]; then
    echo "E: Could not get lock /var/lib/apt/lists/lock. It is held by process 1709 (apt-get)" >&2
    echo "E: Unable to lock directory /var/lib/apt/lists/" >&2
  else
    echo "E: Sperre /var/lib/apt/lists/lock konnte nicht gesetzt werden. Prozess 1709 hält sie." >&2
  fi
}

if [[ " $* " == *" update "* ]]; then
  attempts=0
  [[ ! -f "$APT_UPDATE_ATTEMPTS" ]] || attempts=$(cat "$APT_UPDATE_ATTEMPTS")
  attempts=$((attempts + 1))
  printf '%s\n' "$attempts" > "$APT_UPDATE_ATTEMPTS"

  if [[ "$APT_SCENARIO" == "non-lock-error" ]]; then
    echo "E: The repository is not signed" >&2
    exit 100
  fi
  if [[ "$APT_SCENARIO" == "persistent-lock" || $attempts -eq 1 ]]; then
    apt_lists_lock_error
    exit 100
  fi
  exit 0
fi

if [[ " $* " == *" install "* ]]; then
  attempts=0
  [[ ! -f "$APT_INSTALL_ATTEMPTS" ]] || attempts=$(cat "$APT_INSTALL_ATTEMPTS")
  attempts=$((attempts + 1))
  printf '%s\n' "$attempts" > "$APT_INSTALL_ATTEMPTS"
  if [[ "$APT_SCENARIO" == "install-lock" && $attempts -eq 1 ]]; then
    echo "E: Could not get lock /var/cache/apt/archives/lock. It is held by process 2048 (apt-get)" >&2
    exit 100
  fi

  cat > "$TEST_BIN/ansible-playbook" <<'ANSIBLE'
#!/bin/bash
exit 0
ANSIBLE
  chmod +x "$TEST_BIN/ansible-playbook"
  exit 0
fi

exit 2
SCRIPT

chmod +x "$FAKE_BIN/sudo" "$FAKE_BIN/apt-get"

run_provision() {
  local name=$1
  local scenario=$2
  local timeout=$3
  local case_root="$TMP_ROOT/$name"
  mkdir -p "$case_root/home"
  rm -f "$FAKE_BIN/ansible-playbook"

  export APT_CALLS="$case_root/apt-calls"
  export APT_UPDATE_ATTEMPTS="$case_root/apt-update-attempts"
  export APT_INSTALL_ATTEMPTS="$case_root/apt-install-attempts"
  export APT_SCENARIO="$scenario"
  export TEST_BIN="$FAKE_BIN"

  set +e
  PROVISION_OUTPUT=$(cd "$REPO_ROOT" && \
    PATH="$FAKE_BIN:/usr/bin:/bin" \
    HOME="$case_root/home" \
    OSTYPE=linux-gnu \
    PROVISION_LOCK_DIR="$case_root/provision.lock" \
    PROVISION_LOG_DIR="$case_root/logs" \
    PI_SESSION_STALENESS_RECONCILE_BIN=/usr/bin/true \
    APT_LOCK_RETRY_TIMEOUT_SECONDS="$timeout" \
    APT_LOCK_RETRY_INTERVAL_SECONDS=0 \
    bin/provision 2>&1)
  PROVISION_STATUS=$?
  set -e
}

run_provision retry transient-lock 10
[[ $PROVISION_STATUS -eq 0 ]]
[[ $(cat "$APT_UPDATE_ATTEMPTS") == 2 ]]
[[ $(wc -l < "$APT_CALLS" | tr -d ' ') == 3 ]]
grep -Fq "process 1709 (apt-get)" <<< "$PROVISION_OUTPUT"
grep -Fq "Retrying apt-get" <<< "$PROVISION_OUTPUT"

run_provision install install-lock 10
[[ $PROVISION_STATUS -eq 0 ]]
[[ $(cat "$APT_INSTALL_ATTEMPTS") == 2 ]]
grep -Fq "process 2048 (apt-get)" <<< "$PROVISION_OUTPUT"

run_provision timeout persistent-lock 0
[[ $PROVISION_STATUS -ne 0 ]]
[[ $(cat "$APT_UPDATE_ATTEMPTS") == 1 ]]
grep -Fq "process 1709 (apt-get)" <<< "$PROVISION_OUTPUT"
grep -Fq "Timed out after 0s" <<< "$PROVISION_OUTPUT"

run_provision non-lock non-lock-error 10
[[ $PROVISION_STATUS -ne 0 ]]
[[ $(cat "$APT_UPDATE_ATTEMPTS") == 1 ]]
grep -Fq "The repository is not signed" <<< "$PROVISION_OUTPUT"
if grep -Fq "Retrying apt-get" <<< "$PROVISION_OUTPUT"; then
  echo "Non-lock apt failure was retried" >&2
  exit 1
fi

printf '%s\n' "Provision apt lock retry behavior passed"
