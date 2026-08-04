#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp_root=$(mktemp -d)
cleanup() { rm -rf "$tmp_root"; }
trap cleanup EXIT
mkdir -p "$tmp_root/bin" "$tmp_root/home" "$tmp_root/logs" "$tmp_root/state"

cat > "$tmp_root/bin/ansible-playbook" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${GH_TOKEN-}" "${GITHUB_TOKEN-}" "${MISE_GITHUB_TOKEN-}" > "$TOKEN_OUTPUT"
EOF
chmod +x "$tmp_root/bin/ansible-playbook"

(
  cd "$repo_root"
  PATH="$tmp_root/bin:$PATH" \
  HOME="$tmp_root/home" \
  OSTYPE=linux-gnu \
  XDG_STATE_HOME="$tmp_root/state" \
  PROVISION_LOG_DIR="$tmp_root/logs" \
  PROVISION_LOCK_DIR="$tmp_root/lock" \
  TOKEN_OUTPUT="$tmp_root/tokens" \
  GH_TOKEN=valid-token \
  GITHUB_TOKEN=stale-token \
  MISE_GITHUB_TOKEN= \
  bin/provision --check
) >/dev/null

{
  IFS= read -r actual_gh_token
  IFS= read -r actual_github_token
  IFS= read -r actual_mise_token
} < "$tmp_root/tokens"
[[ "$actual_gh_token" == valid-token ]] || exit 1
[[ "$actual_github_token" == stale-token ]] || exit 1
[[ "$actual_mise_token" == valid-token ]] || exit 1

printf 'PASS  provision gives mise the GH_TOKEN credential when its token is unset\n'
