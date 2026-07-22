#!/bin/bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_ROOT=$(mktemp -d)
cleanup() { rm -rf "$TMP_ROOT"; }
trap cleanup EXIT
mkdir -p "$TMP_ROOT/bin" "$TMP_ROOT/home" "$TMP_ROOT/logs" "$TMP_ROOT/state" "$TMP_ROOT/no-git-bin" "$TMP_ROOT/no-git-logs" "$TMP_ROOT/no-git-state"
real_git=$(command -v git)

cat > "$TMP_ROOT/bin/ansible-playbook" <<'EOF'
#!/bin/bash
printf 'PLAY RECAP *********************************************************************\n'
printf 'localhost                  : ok=1 changed=0 unreachable=0 failed=0 skipped=0 rescued=0 ignored=0\n'
EOF
cat > "$TMP_ROOT/bin/brew" <<EOF
#!/bin/bash
[[ "\${1:-}" == --prefix ]] && printf '%s\n' '$TMP_ROOT/homebrew'
EOF
cat > "$TMP_ROOT/bin/dscl" <<EOF
#!/bin/bash
printf 'UserShell: %s\n' '$TMP_ROOT/homebrew/bin/zsh'
EOF
cat > "$TMP_ROOT/bin/say" <<'EOF'
#!/bin/bash
exit 0
EOF
cat > "$TMP_ROOT/bin/git" <<EOF
#!/bin/bash
real_git='$real_git'
saw_status=false
saw_porcelain=false
saw_untracked_normal=false
for arg in "\$@"; do
  [[ "\$arg" == "status" ]] && saw_status=true
  [[ "\$arg" == "--porcelain" ]] && saw_porcelain=true
  [[ "\$arg" == "--untracked-files=normal" ]] && saw_untracked_normal=true
done
if \$saw_status && \$saw_porcelain && \$saw_untracked_normal; then
  "\$real_git" "\$@"
  status=\$?
  [[ \$status -eq 0 ]] || exit \$status
  printf '?? .pi/\n?? .pi-subagents/\n?? .repo.yml\n'
else
  exec "\$real_git" "\$@"
fi
EOF
cat > "$TMP_ROOT/no-git-bin/git" <<'EOF'
#!/bin/bash
exit 1
EOF
chmod +x "$TMP_ROOT/bin/"* "$TMP_ROOT/no-git-bin/git"

expected_root=$(cd "$REPO_ROOT" && pwd -P)
expected_branch=$(git -C "$REPO_ROOT" symbolic-ref --short -q HEAD || printf 'detached')
expected_commit=$(git -C "$REPO_ROOT" rev-parse HEAD)
if [[ -n "$(git -C "$REPO_ROOT" status --porcelain --untracked-files=normal)" ]]; then
  expected_state=dirty
else
  expected_state=clean
fi

(
  cd "$REPO_ROOT"
  PATH="$TMP_ROOT/bin:$PATH" \
  HOME="$TMP_ROOT/home" \
  XDG_STATE_HOME="$TMP_ROOT/state" \
  PROVISION_LOG_DIR="$TMP_ROOT/logs" \
  PROVISION_LOCK_DIR="$TMP_ROOT/lock" \
  bin/provision --check --extra-vars ansible_become_pass=unique-secret \
    --extra-vars=ansible_become_pass=equals-secret \
    -eansible_become_pass=compact-secret --tags provenance
) > "$TMP_ROOT/output" 2>&1

log_path=$(readlink "$TMP_ROOT/logs/provision-latest.log")
[[ -f "$log_path" ]]
grep -Fq "Provision source worktree: $expected_root" "$log_path"
grep -Fq "Provision source branch: $expected_branch" "$log_path"
grep -Fq "Provision source commit: $expected_commit" "$log_path"
grep -Fq "Provision source repository state: $expected_state" "$log_path"
grep -Fq 'Provision invocation arguments: --check --extra-vars ansible_become_pass=[REDACTED] --extra-vars=ansible_become_pass=[REDACTED] -eansible_become_pass=[REDACTED] --tags provenance' "$log_path"
grep -Fq 'Executing command: ansible-playbook --inventory localhost, --connection local playbook.yml --check --extra-vars ansible_become_pass=[REDACTED] --extra-vars=ansible_become_pass=[REDACTED] -eansible_become_pass=[REDACTED] --tags provenance' "$log_path"
! grep -Eq 'unique-secret|equals-secret|compact-secret' "$log_path"
grep -Eq 'Provision started at: [0-9]{4}-[0-9]{2}-[0-9]{2}T' "$log_path"
grep -Fq 'localhost                  : ok=1 changed=0 unreachable=0 failed=0' "$log_path"
printf 'PASS  provision log records source provenance, redacts secrets, and keeps later args visible\n'

(
  cd "$REPO_ROOT"
  PATH="$TMP_ROOT/no-git-bin:$TMP_ROOT/bin:$PATH" \
  HOME="$TMP_ROOT/home" \
  XDG_STATE_HOME="$TMP_ROOT/no-git-state" \
  PROVISION_LOG_DIR="$TMP_ROOT/no-git-logs" \
  PROVISION_LOCK_DIR="$TMP_ROOT/no-git-lock" \
  bin/provision --check
) > "$TMP_ROOT/no-git-output" 2>&1

no_git_log_path=$(readlink "$TMP_ROOT/no-git-logs/provision-latest.log")
[[ -f "$no_git_log_path" ]]
grep -Fq 'Provision source worktree: unknown' "$no_git_log_path"
grep -Fq 'Provision source branch: unknown' "$no_git_log_path"
grep -Fq 'Provision source commit: unknown' "$no_git_log_path"
grep -Fq 'Provision source repository state: unknown' "$no_git_log_path"
printf 'PASS  provision log falls back to unknown provenance when git is unavailable\n'
