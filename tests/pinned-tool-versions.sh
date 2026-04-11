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
INTEGRATION_WORKFLOW="$REPO_ROOT/.github/workflows/integration-test.yml"
REVIEW_WORKFLOW="$REPO_ROOT/.github/workflows/renovate-review.yml"

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

run_catalog_checks() {
  assert_contains "$PLAYBOOK" "vars_files:" "playbook loads shared vars files"
  assert_contains "$PLAYBOOK" "- vars/tool_versions.yml" "playbook loads vars/tool_versions.yml"
  assert_contains "$CATALOG" "tool_versions:" "catalog defines tool_versions root"
  assert_contains "$CATALOG" "github_releases:" "catalog defines github release pins"
  assert_contains "$CATALOG" "git_tags:" "catalog defines git tag pins"
  assert_contains "$CATALOG" "runtimes:" "catalog defines runtime pins"
  assert_contains "$CATALOG" "compatibility:" "catalog defines compatibility pins"
  assert_contains "$CATALOG" "fzf: v0.71.0" "catalog pins fzf"
  assert_contains "$CATALOG" "ripgrep: 15.1.0" "catalog pins ripgrep"
  assert_contains "$CATALOG" "delta: 0.19.2" "catalog pins delta"
  assert_contains "$CATALOG" "tmux: v3.6a" "catalog pins tmux"
  assert_contains "$CATALOG" "neovim: v0.12.1" "catalog pins neovim"
  assert_contains "$CATALOG" "yq: v4.52.5" "catalog pins yq"
  assert_contains "$CATALOG" "zoxide: v0.9.9" "catalog pins zoxide"
  assert_contains "$CATALOG" "mise: v2026.4.8" "catalog pins mise"
  assert_contains "$CATALOG" "node: 24.14.1" "catalog pins Node.js"
  assert_contains "$CATALOG" "neovim_glibc_legacy: v0.10.4" "catalog preserves legacy neovim compatibility pin"
}

run_install_checks() {
  assert_contains "$LINUX_INSTALLS" "pinned_release_tag: \"{{ tool_versions.github_releases.fzf }}\"" "linux fzf release install uses catalog pin"
  assert_contains "$LINUX_INSTALLS" "version: \"{{ tool_versions.git_tags.fzf }}\"" "linux fzf shell clone uses catalog tag"
  assert_contains "$LINUX_INSTALLS" "pinned_release_tag: \"{{ tool_versions.github_releases.ripgrep }}\"" "linux ripgrep install uses catalog pin"
  assert_contains "$LINUX_INSTALLS" "pinned_release_tag: \"{{ tool_versions.github_releases.delta }}\"" "linux delta install uses catalog pin"
  assert_contains "$LINUX_INSTALLS" "pinned_release_tag: \"{{ tool_versions.github_releases.tmux }}\"" "linux tmux install uses catalog pin"
  assert_contains "$LINUX_INSTALLS" "tool_versions.github_releases.neovim" "linux neovim default install uses catalog pin"
  assert_contains "$LINUX_INSTALLS" "tool_versions.compatibility.neovim_glibc_legacy" "linux neovim legacy override uses catalog pin"
  assert_contains "$LINUX_INSTALLS" "pinned_release_tag: \"{{ tool_versions.github_releases.yq }}\"" "linux yq install uses catalog pin"
  assert_contains "$LINUX_INSTALLS" "pinned_release_tag: \"{{ tool_versions.github_releases.zoxide }}\"" "linux zoxide install uses catalog pin"
  assert_contains "$LINUX_INSTALLS" "shell: curl -fsSL https://mise.run | sh" "linux mise install keeps the upstream shell installer"
  assert_contains "$LINUX_INSTALLS" "environment:" "linux mise install defines an environment block"
  assert_contains "$LINUX_INSTALLS" "MISE_VERSION: \"{{ tool_versions.runtimes.mise }}\"" "linux mise install exports pinned MISE_VERSION"
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
}

run_renovate_checks() {
  assert_contains "$RENOVATE_CONFIG" "\"extends\": [\"config:recommended\"]" "renovate config extends config:recommended"
  assert_contains "$RENOVATE_CONFIG" "\"minimumReleaseAge\": \"7 days\"" "renovate config uses a seven-day release age"
  assert_contains "$RENOVATE_CONFIG" "\"fileMatch\": [\"^vars/tool_versions\\\\.yml$\"]" "renovate regex manager targets vars/tool_versions.yml"
  assert_contains "$RENOVATE_CONFIG" "datasource=(?<datasource>[a-z-]+)" "renovate regex manager reads datasource annotations"
  assert_contains "$RENOVATE_CONFIG" "depName=(?<depName>[^\\\\s]+)" "renovate regex manager reads depName annotations"
}

run_integration_checks() {
  assert_contains "$INTEGRATION_WORKFLOW" "bash tests/pinned-tool-versions.sh core" "integration workflow runs pinned-tool-versions regression test"
  assert_contains "$INTEGRATION_WORKFLOW" "vars/tool_versions.yml" "integration workflow reads the shared version catalog"
  assert_contains "$INTEGRATION_WORKFLOW" "Expected versions verified" "integration workflow verifies pinned versions"
}

run_review_workflow_checks() {
  assert_contains "$REVIEW_WORKFLOW" "permissions:" "review workflow declares explicit permissions"
  assert_contains "$REVIEW_WORKFLOW" "pull-requests: write" "review workflow can post PR comments"
  assert_not_contains "$REVIEW_WORKFLOW" "contains(github.event.pull_request.user.login, 'renovate')" "review workflow no longer uses broad Renovate substring gating"
  assert_contains "$REVIEW_WORKFLOW" "github.event.pull_request.user.login == 'renovate[bot]'" "review workflow allows renovate[bot]"
  assert_contains "$REVIEW_WORKFLOW" "github.event.pull_request.user.login == 'renovate-bot'" "review workflow allows renovate-bot"
  assert_contains "$REVIEW_WORKFLOW" "timeout-minutes: 10" "review workflow sets a job timeout"
  assert_contains "$REVIEW_WORKFLOW" "actions/checkout@v4" "review workflow uses GitHub Actions checkout"
  assert_contains "$REVIEW_WORKFLOW" "npm install -g @anthropic-ai/claude-code" "review workflow installs Claude Code CLI"
  assert_contains "$REVIEW_WORKFLOW" "gh pr view" "review workflow reads the PR metadata"
  assert_contains "$REVIEW_WORKFLOW" "--json title,body" "review workflow fetches PR title and body"
  assert_contains "$REVIEW_WORKFLOW" "claude -p" "review workflow runs Claude in prompt mode"
  assert_contains "$REVIEW_WORKFLOW" "--allowedTools 'Read,Grep,Glob'" "review workflow restricts Claude tools"
  assert_contains "$REVIEW_WORKFLOW" "gh pr comment" "review workflow posts the review comment"
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
