#!/bin/bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT
mkdir -p "$TMP_ROOT/bin" "$TMP_ROOT/home" "$TMP_ROOT/logs" "$TMP_ROOT/state"

cat >"$TMP_ROOT/bin/ansible-playbook" <<'EOF'
#!/bin/bash
printf 'PLAY RECAP *********************************************************************\n'
printf 'localhost : ok=1 changed=0 unreachable=0 failed=0\n'
EOF
cat >"$TMP_ROOT/bin/brew" <<EOF
#!/bin/bash
[[ "\${1:-}" == --prefix ]] && printf '%s\n' '$TMP_ROOT/homebrew'
EOF
cat >"$TMP_ROOT/bin/dscl" <<EOF
#!/bin/bash
printf 'UserShell: %s\n' '$TMP_ROOT/homebrew/bin/zsh'
EOF
cat >"$TMP_ROOT/bin/say" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$TMP_ROOT/bin/"*

(
  cd "$REPO_ROOT"
  PATH="$TMP_ROOT/bin:$PATH" \
  HOME="$TMP_ROOT/home" \
  XDG_STATE_HOME="$TMP_ROOT/state" \
  PROVISION_LOG_DIR="$TMP_ROOT/logs" \
  PROVISION_LOCK_DIR="$TMP_ROOT/lock" \
  bin/provision --check --extra-vars ansible_become_pass=unique-secret \
    --extra-vars=ansible_become_pass=equals-secret \
    -eansible_become_pass=compact-secret --tags after-secret
) >"$TMP_ROOT/output" 2>&1

log_path=$(readlink "$TMP_ROOT/logs/provision-latest.log")
[[ -f "$log_path" ]]
grep -Fq 'Provision invocation arguments: --check --extra-vars ansible_become_pass=[REDACTED] --extra-vars=ansible_become_pass=[REDACTED] -eansible_become_pass=[REDACTED] --tags after-secret' "$log_path"
grep -Fq 'Executing command: ansible-playbook --inventory localhost, --connection local playbook.yml --check --extra-vars ansible_become_pass=[REDACTED] --extra-vars=ansible_become_pass=[REDACTED] -eansible_become_pass=[REDACTED] --tags after-secret' "$log_path"
! grep -Eq 'unique-secret|equals-secret|compact-secret' "$log_path"
printf 'PASS  provision log redacts secret arguments without hiding later arguments\n'
