#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
PLAYBOOK="$REPO_ROOT/playbook.yml"
CATALOG="$REPO_ROOT/vars/tool_versions.yml"
LINUX_INSTALLS="$REPO_ROOT/roles/linux/tasks/install_packages.yml"
LINUX_MAIN="$REPO_ROOT/roles/linux/tasks/main.yml"
COMMON_MAIN="$REPO_ROOT/roles/common/tasks/main.yml"
MACOS_MAIN="$REPO_ROOT/roles/macos/tasks/main.yml"
RENOVATE_CONFIG="$REPO_ROOT/renovate.json"
RENOVATE_RUN_WORKFLOW="$REPO_ROOT/.github/workflows/renovate.yml"
RENOVATE_SETUP_DOC="$REPO_ROOT/docs/renovate-github-app.md"
INTEGRATION_WORKFLOW="$REPO_ROOT/.github/workflows/integration-test.yml"
REVIEW_WORKFLOW="$REPO_ROOT/.github/workflows/renovate-review.yml"
WORKFLOWS_DIR="$REPO_ROOT/.github/workflows"
CODEX_REVIEW_DOC="$REPO_ROOT/docs/codex-github-review.md"

pass=0
fail=0

pass_case() {
  pass=$((pass + 1))
  printf 'PASS  %s\n' "$1"
}

fail_case() {
  fail=$((fail + 1))
  printf 'FAIL  %s\n' "$1"
  printf '      %s\n' "$2"
}

assert_contains() {
  local path="$1" needle="$2" name="$3"

  if rg -n -F -- "$needle" "$path" >/dev/null 2>&1; then
    pass_case "$name"
  else
    fail_case "$name" "missing '$needle' in $path"
  fi
}

assert_not_contains() {
  local path="$1" needle="$2" name="$3"

  if rg -n -F -- "$needle" "$path" >/dev/null 2>&1; then
    local match
    match="$(rg -n -F -- "$needle" "$path" | head -n 1)"
    fail_case "$name" "unexpected '$needle' in $path at $match"
  else
    pass_case "$name"
  fi
}

assert_yaml_matches() {
  local path="$1" query="$2" regex="$3" name="$4"
  local value

  value="$(yq -r "$query" "$path" 2>/dev/null || true)"

  if [[ -n "$value" && "$value" != "null" && "$value" =~ $regex ]]; then
    pass_case "$name"
  else
    fail_case "$name" "expected $query in $path to match $regex, got '${value:-<empty>}'"
  fi
}

run_catalog_checks() {
  assert_contains "$PLAYBOOK" "vars_files:" "playbook loads shared vars files"
  assert_contains "$PLAYBOOK" "- vars/tool_versions.yml" "playbook loads vars/tool_versions.yml"
  assert_contains "$CATALOG" "tool_versions:" "catalog defines tool_versions root"
  assert_contains "$CATALOG" "github_releases:" "catalog defines github release pins"
  assert_contains "$CATALOG" "git_tags:" "catalog defines git tag pins"
  assert_contains "$CATALOG" "runtimes:" "catalog defines runtime pins"
  assert_not_contains "$CATALOG" "compatibility:" "catalog no longer defines legacy compatibility pins"
  assert_yaml_matches "$CATALOG" '.tool_versions.github_releases.fzf' '^v[0-9]+\.[0-9]+\.[0-9]+$' "catalog pins fzf"
  assert_yaml_matches "$CATALOG" '.tool_versions.github_releases.ripgrep' '^[0-9]+\.[0-9]+\.[0-9]+$' "catalog pins ripgrep"
  assert_yaml_matches "$CATALOG" '.tool_versions.github_releases.delta' '^[0-9]+\.[0-9]+\.[0-9]+$' "catalog pins delta"
  assert_yaml_matches "$CATALOG" '.tool_versions.github_releases.tmux' '^v[0-9]+\.[0-9]+[a-z]?$' "catalog pins tmux"
  assert_yaml_matches "$CATALOG" '.tool_versions.github_releases.neovim' '^v[0-9]+\.[0-9]+\.[0-9]+$' "catalog pins neovim"
  assert_yaml_matches "$CATALOG" '.tool_versions.github_releases.yq' '^v[0-9]+\.[0-9]+\.[0-9]+$' "catalog pins yq"
  assert_yaml_matches "$CATALOG" '.tool_versions.github_releases.zoxide' '^v[0-9]+\.[0-9]+\.[0-9]+$' "catalog pins zoxide"
  assert_yaml_matches "$CATALOG" '.tool_versions.runtimes.mise' '^v[0-9]+\.[0-9]+\.[0-9]+$' "catalog pins mise"
  assert_yaml_matches "$CATALOG" '.tool_versions.runtimes.node' '^[0-9]+\.[0-9]+\.[0-9]+$' "catalog pins Node.js"
  assert_not_contains "$CATALOG" "neovim_glibc_legacy: v0.10.4" "catalog no longer preserves legacy neovim compatibility pin"
}

run_install_checks() {
  assert_contains "$LINUX_INSTALLS" "pinned_release_tag: \"{{ tool_versions.github_releases.fzf }}\"" "linux fzf release install uses catalog pin"
  assert_contains "$LINUX_INSTALLS" "version: \"{{ tool_versions.git_tags.fzf }}\"" "linux fzf shell clone uses catalog tag"
  assert_contains "$LINUX_INSTALLS" "pinned_release_tag: \"{{ tool_versions.github_releases.ripgrep }}\"" "linux ripgrep install uses catalog pin"
  assert_contains "$LINUX_INSTALLS" "pinned_release_tag: \"{{ tool_versions.github_releases.delta }}\"" "linux delta install uses catalog pin"
  assert_contains "$LINUX_INSTALLS" "pinned_release_tag: \"{{ tool_versions.github_releases.tmux }}\"" "linux tmux install uses catalog pin"
  assert_contains "$LINUX_INSTALLS" "pinned_release_tag: \"{{ tool_versions.github_releases.neovim }}\"" "linux neovim install uses catalog pin directly"
  assert_not_contains "$LINUX_INSTALLS" "tool_versions.compatibility.neovim_glibc_legacy" "linux neovim no longer uses legacy glibc override"
  assert_contains "$LINUX_INSTALLS" "pinned_release_tag: \"{{ tool_versions.github_releases.yq }}\"" "linux yq install uses catalog pin"
  assert_contains "$LINUX_INSTALLS" "pinned_release_tag: \"{{ tool_versions.github_releases.zoxide }}\"" "linux zoxide install uses catalog pin"
  assert_contains "$LINUX_INSTALLS" "shell: curl -fsSL https://mise.run | sh" "linux mise install keeps the upstream shell installer"
  assert_contains "$LINUX_INSTALLS" "environment:" "linux mise install defines an environment block"
  assert_contains "$LINUX_INSTALLS" "MISE_VERSION: \"{{ tool_versions.runtimes.mise }}\"" "linux mise install exports pinned MISE_VERSION"
  assert_contains "$LINUX_INSTALLS" "Check installed mise version" "linux tasks check the installed mise version"
  assert_contains "$LINUX_INSTALLS" "linux_mise_version.stdout | default('')" "linux mise install compares the installed version against the pin"
  assert_contains "$LINUX_MAIN" "version: \"{{ tool_versions.git_tags.tpm }}\"" "linux tpm clone uses catalog tag"
  assert_contains "$COMMON_MAIN" "version: \"{{ tool_versions.git_tags.superpowers }}\"" "common superpowers clone uses catalog tag"
  assert_contains "$COMMON_MAIN" "install node@{{ tool_versions.runtimes.node }}" "common Linux Node install uses pinned version"
  assert_contains "$COMMON_MAIN" "node@{{ tool_versions.runtimes.node }}" "common Linux Node install uses pinned version"
  assert_contains "$COMMON_MAIN" "awk '\$1 == \\\"node\\\" && \$2 == \\\"{{ tool_versions.runtimes.node }}\\\" { found = 1 } END { exit(found ? 0 : 1) }'" "common Linux Node detection uses exact version-column matching"
  assert_contains "$COMMON_MAIN" "bash -s -- latest" "common Claude installer makes latest explicit"
  assert_contains "$MACOS_MAIN" "version: \"{{ tool_versions.git_tags.tpm }}\"" "macOS tpm clone uses catalog tag"
  assert_contains "$MACOS_MAIN" "node@{{ tool_versions.runtimes.node }}" "macOS Node install uses pinned version"
  assert_contains "$MACOS_MAIN" "awk '\$1 == \\\"node\\\" && \$2 == \\\"{{ tool_versions.runtimes.node }}\\\" { found = 1 } END { exit(found ? 0 : 1) }'" "macOS Node detection uses exact version-column matching"
  assert_not_contains "$LINUX_INSTALLS" "version: master" "linux install tasks no longer use master"
  assert_not_contains "$LINUX_MAIN" "version: master" "linux main tasks no longer use master"
  assert_not_contains "$COMMON_MAIN" "version: main" "common tasks no longer use main for superpowers"
  assert_not_contains "$COMMON_MAIN" "node@lts" "common tasks no longer use floating Linux Node aliases"
  assert_not_contains "$COMMON_MAIN" "linux_node_lts" "common tasks no longer reference the removed Linux Node LTS register"
  assert_not_contains "$COMMON_MAIN" "rg -F 'node  {{ tool_versions.runtimes.node }}'" "common Linux Node detection no longer uses substring matching"
  assert_not_contains "$COMMON_MAIN" "latest node@lts" "common tasks no longer resolve latest Linux Node LTS"
  assert_not_contains "$MACOS_MAIN" "latest node@lts" "macOS tasks no longer resolve latest Node LTS"
  assert_not_contains "$MACOS_MAIN" "('node  ' ~ tool_versions.runtimes.node) in installed_node_versions.stdout" "macOS Node detection no longer uses substring matching against stdout"
  assert_not_contains "$LINUX_INSTALLS" "shell: MISE_VERSION={{ tool_versions.runtimes.mise }} curl -fsSL https://mise.run | sh" "linux mise install no longer uses the inline MISE_VERSION shell form"
  assert_not_contains "$LINUX_INSTALLS" "- mise_check.rc != 0" "linux mise install no longer only runs when the binary is missing"
}

run_renovate_checks() {
  assert_contains "$RENOVATE_CONFIG" "\"extends\": [\"config:recommended\"]" "renovate config extends config:recommended"
  assert_contains "$RENOVATE_CONFIG" "\"minimumReleaseAge\": \"7 days\"" "renovate config uses a seven-day release age"
  assert_contains "$RENOVATE_CONFIG" "\"fileMatch\": [\"^vars/tool_versions\\\\.yml$\"]" "renovate regex manager targets vars/tool_versions.yml"
  assert_contains "$RENOVATE_CONFIG" "datasource=(?<datasource>[a-z-]+)" "renovate regex manager reads datasource annotations"
  assert_contains "$RENOVATE_CONFIG" "depName=(?<depName>[^\\\\s]+)" "renovate regex manager reads depName annotations"
  if jq -e '
    any(.packageRules[]?;
      .description == "Keep superpowers updates explicit and easy to spot"
      and .matchManagers == ["custom.regex"]
      and .matchPackageNames == ["obra/superpowers"]
      and .commitMessageTopic == "superpowers"
      and .addLabels == ["superpowers"]
    )
  ' "$RENOVATE_CONFIG" >/dev/null 2>&1; then
    pass_case "renovate config defines a dedicated superpowers rule"
  else
    fail_case "renovate config defines a dedicated superpowers rule" "missing packageRules entry for obra/superpowers with the expected fields in $RENOVATE_CONFIG"
  fi
  assert_contains "$RENOVATE_RUN_WORKFLOW" "workflow_dispatch:" "renovate workflow supports manual dispatch"
  assert_contains "$RENOVATE_RUN_WORKFLOW" "- cron: '23 3 * * *'" "renovate workflow runs daily on the configured schedule"
  assert_yaml_matches "$RENOVATE_RUN_WORKFLOW" '.jobs.renovate.steps[] | select(.id == "app_token").uses' '^actions/create-github-app-token@v[0-9]+(\.[0-9]+){0,2}$' "renovate workflow mints a GitHub App token"
  assert_yaml_matches "$RENOVATE_RUN_WORKFLOW" '.jobs.renovate.steps[] | select(.name == "Checkout").uses' '^actions/checkout@v[0-9]+(\.[0-9]+){0,2}$' "renovate workflow checks out the repository"
  assert_yaml_matches "$RENOVATE_RUN_WORKFLOW" '.jobs.renovate.steps[] | select(.name == "Self-hosted Renovate").uses' '^renovatebot/github-action@v[0-9]+(\.[0-9]+){0,2}$' "renovate workflow runs the official Renovate GitHub Action"
  assert_not_contains "$RENOVATE_RUN_WORKFLOW" "configurationFile:" "renovate workflow does not pass a separate global config file"
  assert_contains "$RENOVATE_RUN_WORKFLOW" 'token: ${{ steps.app_token.outputs.token }}' "renovate workflow passes the GitHub App token to Renovate"
  assert_contains "$RENOVATE_RUN_WORKFLOW" 'repositories: ${{ github.event.repository.name }}' "renovate workflow scopes the GitHub App token to the current repository"
  assert_contains "$RENOVATE_RUN_WORKFLOW" 'RENOVATE_REPOSITORIES: ${{ github.repository }}' "renovate workflow tells self-hosted Renovate to process the current repository"
  assert_not_contains "$RENOVATE_RUN_WORKFLOW" "GITHUB_TOKEN" "renovate workflow does not authenticate Renovate with GITHUB_TOKEN"
  assert_contains "$RENOVATE_SETUP_DOC" "RENOVATE_APP_ID" "GitHub App setup doc lists the App ID secret"
  assert_contains "$RENOVATE_SETUP_DOC" "RENOVATE_APP_PRIVATE_KEY" "GitHub App setup doc lists the App private key secret"
  assert_contains "$RENOVATE_SETUP_DOC" "RENOVATE_APP_SLUG" "GitHub App setup doc lists the required repo variable"
}

run_integration_checks() {
  assert_contains "$INTEGRATION_WORKFLOW" "pull_request:" "integration workflow runs on pull requests"
  assert_not_contains "$INTEGRATION_WORKFLOW" "push:" "integration workflow no longer runs on post-merge pushes"
  assert_contains "$INTEGRATION_WORKFLOW" "bash tests/pinned-tool-versions.sh core" "integration workflow runs pinned-tool-versions regression test"
  assert_contains "$INTEGRATION_WORKFLOW" "vars/tool_versions.yml" "integration workflow reads the shared version catalog"
  assert_contains "$INTEGRATION_WORKFLOW" 'local_bin="$HOME/.local/bin"' "integration workflow resolves the user-local binary directory"
  assert_contains "$INTEGRATION_WORKFLOW" 'user_mise="$local_bin/mise"' "integration workflow checks the provisioned mise binary"
  assert_contains "$INTEGRATION_WORKFLOW" "version -J | jq -r '.version | split(\" \")[0]'" "integration workflow reads the mise version from JSON output"
  assert_not_contains "$INTEGRATION_WORKFLOW" '"$user_mise" --version | awk '\''{print $2}'\''' "integration workflow no longer reads the mise version from the second text token"
  assert_contains "$INTEGRATION_WORKFLOW" "mise_config_file=\"\$HOME/.config/mise/config.toml\"" "integration workflow resolves the global mise config file"
  assert_contains "$INTEGRATION_WORKFLOW" 'config get --file "$mise_config_file" tools.node' "integration workflow reads the global Node version from the global mise config"
  assert_not_contains "$INTEGRATION_WORKFLOW" "ls --global --json node" "integration workflow no longer reads the global Node version from mise ls JSON"
  assert_not_contains "$INTEGRATION_WORKFLOW" "jq -r '.[0].version // empty'" "integration workflow no longer parses the global Node version with jq"
  assert_not_contains "$INTEGRATION_WORKFLOW" "current node | awk '{print \$2}'" "integration workflow no longer parses mise current output with awk"
  assert_contains "$INTEGRATION_WORKFLOW" 'user_yq="$local_bin/yq"' "integration workflow checks the provisioned yq binary"
  assert_contains "$INTEGRATION_WORKFLOW" 'user_delta="$local_bin/delta"' "integration workflow checks the provisioned delta binary"
  assert_contains "$INTEGRATION_WORKFLOW" 'user_nvim="$local_bin/nvim"' "integration workflow checks the provisioned neovim binary"
  assert_contains "$INTEGRATION_WORKFLOW" 'user_zoxide="$local_bin/zoxide"' "integration workflow checks the provisioned zoxide binary"
  assert_contains "$INTEGRATION_WORKFLOW" 'user_fzf="$local_bin/fzf"' "integration workflow checks the provisioned fzf binary"
  assert_contains "$INTEGRATION_WORKFLOW" 'system_rg="/usr/bin/rg"' "integration workflow checks the ripgrep package-installed path"
  assert_contains "$INTEGRATION_WORKFLOW" 'system_tmux="/usr/local/bin/tmux"' "integration workflow checks the tmux symlink path"
  assert_contains "$INTEGRATION_WORKFLOW" "Expected versions verified" "integration workflow verifies pinned versions"
}

run_review_workflow_checks() {
  if [[ ! -e "$REVIEW_WORKFLOW" ]]; then
    pass_case "review workflow has been removed"
  else
    fail_case "review workflow has been removed" "unexpected file present at $REVIEW_WORKFLOW"
  fi

  assert_not_contains "$WORKFLOWS_DIR" "CLAUDE_CODE_OAUTH_TOKEN" "review workflow no longer references the Claude OAuth token"
  assert_not_contains "$WORKFLOWS_DIR" "@anthropic-ai/claude-code" "review workflow no longer install Claude Code"
  assert_not_contains "$WORKFLOWS_DIR" "claude -p" "review workflow no longer run Claude prompt mode"

  if [[ -f "$CODEX_REVIEW_DOC" ]]; then
    pass_case "Codex GitHub review setup doc exists"
    assert_contains "$CODEX_REVIEW_DOC" "Codex" "Codex review doc mentions Codex"
    assert_contains "$CODEX_REVIEW_DOC" "GitHub" "Codex review doc mentions GitHub"
    assert_contains "$CODEX_REVIEW_DOC" "code review" "Codex review doc mentions code review"
    assert_contains "$CODEX_REVIEW_DOC" "\`@codex review\`" "Codex review doc includes the manual fallback"
    assert_contains "$CODEX_REVIEW_DOC" "\`CLAUDE_CODE_OAUTH_TOKEN\`" "Codex review doc explains the old Claude secret cleanup"
  else
    fail_case "Codex GitHub review setup doc exists" "missing $CODEX_REVIEW_DOC"
  fi
}

case "${1:-all}" in
  catalog) run_catalog_checks ;;
  installs) run_install_checks ;;
  renovate) run_renovate_checks ;;
  integration) run_integration_checks ;;
  review) run_review_workflow_checks ;;
  core)
    run_catalog_checks
    run_install_checks
    run_renovate_checks
    run_integration_checks
    ;;
  all)
    run_catalog_checks
    run_install_checks
    run_renovate_checks
    run_integration_checks
    run_review_workflow_checks
    ;;
  *)
    echo "usage: $0 [catalog|installs|renovate|integration|review|core|all]" >&2
    exit 1
    ;;
esac

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
