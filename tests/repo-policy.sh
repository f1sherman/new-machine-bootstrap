#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
PLAYBOOK="$REPO_ROOT/playbook.yml"
CATALOG="$REPO_ROOT/vars/tool_versions.yml"
MISE_TOML="$REPO_ROOT/mise.toml"
LINUX_INSTALLS="$REPO_ROOT/roles/linux/tasks/install_packages.yml"
LINUX_MAIN="$REPO_ROOT/roles/linux/tasks/main.yml"
COMMON_MAIN="$REPO_ROOT/roles/common/tasks/main.yml"
COMMON_GITIGNORE="$REPO_ROOT/roles/common/templates/dotfiles/gitignore"
COMMON_ZSH="$REPO_ROOT/roles/common/templates/dotfiles/zshrc.d/50-personal-dev-shell.zsh"
MACOS_BASH_PROFILE="$REPO_ROOT/roles/macos/templates/dotfiles/bash_profile"
CODEX_MAIN_EDIT_HOOK="$REPO_ROOT/roles/common/files/bin/codex-block-main-branch-edits"
CODEX_WORKTREE_HOOK="$REPO_ROOT/roles/common/files/bin/codex-block-worktree-commands"
TMUX_AGENT_WORKTREE="$REPO_ROOT/roles/common/files/bin/tmux-agent-worktree"
TMUX_PANE_LABEL="$REPO_ROOT/roles/common/files/bin/tmux-pane-label"
TMUX_WINDOW_LABEL="$REPO_ROOT/roles/common/files/bin/tmux-window-label"
TMUX_SYNC_REMOTE_TITLE="$REPO_ROOT/roles/common/files/bin/tmux-sync-remote-title"
TMUX_SESSION_NAME="$REPO_ROOT/roles/common/files/bin/tmux-session-name"
LINUX_TMUX_CONF="$REPO_ROOT/roles/linux/files/dotfiles/tmux.conf"
MACOS_TMUX_CONF="$REPO_ROOT/roles/macos/templates/dotfiles/tmux.conf"
MACOS_MAIN="$REPO_ROOT/roles/macos/tasks/main.yml"
MACOS_INSTALLS="$REPO_ROOT/roles/macos/tasks/install_packages.yml"
MACOS_DEFAULT_NPM_PACKAGES="$REPO_ROOT/roles/macos/files/mise/default-npm-packages"
HEAL_TASKS="$REPO_ROOT/roles/common/tasks/heal_mise_node_installs.yml"
MISE_NODE_GLOBALS_TASKS="$REPO_ROOT/roles/common/tasks/install_mise_node_global_tools.yml"
RENOVATE_CONFIG="$REPO_ROOT/renovate.json"
RENOVATE_RUN_WORKFLOW="$REPO_ROOT/.github/workflows/renovate.yml"
RENOVATE_SETUP_DOC="$REPO_ROOT/docs/renovate-github-app.md"
INTEGRATION_WORKFLOW="$REPO_ROOT/.github/workflows/integration-test.yml"
REVIEW_WORKFLOW="$REPO_ROOT/.github/workflows/renovate-review.yml"
CODEX_REVIEW_WORKFLOW="$REPO_ROOT/.github/workflows/codex-pr-review.yml"
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

assert_toml_value_equals_yaml() {
  local toml_path="$1" toml_query="$2" yaml_path="$3" yaml_query="$4" name="$5"
  local toml_value yaml_value

  toml_value="$(yq -p=toml -oy -r "$toml_query" "$toml_path" 2>/dev/null || true)"
  yaml_value="$(yq -r "$yaml_query" "$yaml_path" 2>/dev/null || true)"

  if [[ -n "$toml_value" && "$toml_value" != "null" && "$toml_value" == "$yaml_value" ]]; then
    pass_case "$name"
  else
    fail_case "$name" "expected $toml_query in $toml_path to equal $yaml_query in $yaml_path; got '$toml_value' vs '$yaml_value'"
  fi
}

assert_yaml_equals() {
  local path="$1" query="$2" expected="$3" name="$4"
  local value

  value="$(yq -r "$query" "$path" 2>/dev/null || true)"

  if [[ "$value" == "$expected" ]]; then
    pass_case "$name"
  else
    fail_case "$name" "expected $query in $path to be '$expected', got '${value:-<empty>}'"
  fi
}

extract_codex_vim_mode_ruby() {
  awk '
    $0 == "- name: Configure Codex CLI Vim mode in ~/.codex/config.toml" {
      in_task = 1
      next
    }
    in_task && $0 ~ /^- name:/ {
      exit
    }
    in_task && $0 ~ /<<'\''RUBY'\''$/ {
      capture = 1
      next
    }
    capture && $0 == "    RUBY" {
      exit
    }
    capture {
      sub(/^    /, "")
      print
    }
  ' "$COMMON_MAIN"
}

assert_codex_vim_mode_merge() {
  local name="$1" initial="$2" expected="$3"
  local tmpdir config script output

  tmpdir="$(mktemp -d)"
  config="$tmpdir/config.toml"
  script="$tmpdir/merge.rb"

  extract_codex_vim_mode_ruby >"$script"
  if [[ -n "$initial" ]]; then
    printf '%b' "$initial" >"$config"
  fi

  output="$(CONFIG_FILE="$config" ruby "$script")"
  if [[ "$output" != "changed" ]]; then
    fail_case "$name" "expected first run to report changed, got '$output'"
    rm -rf "$tmpdir"
    return
  fi

  if ! diff -u <(printf '%b' "$expected") "$config" >/dev/null; then
    fail_case "$name" "merged config did not match expected output"
    rm -rf "$tmpdir"
    return
  fi

  output="$(CONFIG_FILE="$config" ruby "$script")"
  if [[ "$output" != "unchanged" ]]; then
    fail_case "$name" "expected second run to report unchanged, got '$output'"
    rm -rf "$tmpdir"
    return
  fi

  if ! diff -u <(printf '%b' "$expected") "$config" >/dev/null; then
    fail_case "$name" "second run changed the merged config"
    rm -rf "$tmpdir"
    return
  fi

  pass_case "$name"
  rm -rf "$tmpdir"
}

run_codex_vim_mode_checks() {
  assert_codex_vim_mode_merge \
    "Codex Vim mode merge creates the TUI section" \
    "" \
    "[tui]\nvim_mode_default = true\n"

  assert_codex_vim_mode_merge \
    "Codex Vim mode merge flips an existing false value" \
    "[tui]\nvim_mode_default = false\n" \
    "[tui]\nvim_mode_default = true\n"

  assert_codex_vim_mode_merge \
    "Codex Vim mode merge preserves other TUI settings" \
    "[tui]\ntheme = \"dark\"\nvim_mode_default = false\nnotifications = true\n\n[projects.\"/tmp/example\"]\ntrust_level = \"trusted\"\n" \
    "[tui]\ntheme = \"dark\"\nvim_mode_default = true\nnotifications = true\n\n[projects.\"/tmp/example\"]\ntrust_level = \"trusted\"\n"

  assert_codex_vim_mode_merge \
    "Codex Vim mode merge preserves dotted TUI keys" \
    "model = \"gpt-5.5\"\ntui.theme = \"dark\"\ntui.vim_mode_default = false\n\n[projects.\"/tmp/example\"]\ntrust_level = \"trusted\"\n" \
    "model = \"gpt-5.5\"\ntui.theme = \"dark\"\ntui.vim_mode_default = true\n\n[projects.\"/tmp/example\"]\ntrust_level = \"trusted\"\n"

  assert_codex_vim_mode_merge \
    "Codex Vim mode merge adds to existing dotted TUI keys" \
    "model = \"gpt-5.5\"\ntui.theme = \"dark\"\n\n[projects.\"/tmp/example\"]\ntrust_level = \"trusted\"\n" \
    "model = \"gpt-5.5\"\ntui.theme = \"dark\"\ntui.vim_mode_default = true\n\n[projects.\"/tmp/example\"]\ntrust_level = \"trusted\"\n"

  assert_codex_vim_mode_merge \
    "Codex Vim mode merge recognizes spaced dotted TUI keys" \
    "model = \"gpt-5.5\"\ntui . session_picker_view = \"recent\"\n\n[projects.\"/tmp/example\"]\ntrust_level = \"trusted\"\n" \
    "model = \"gpt-5.5\"\ntui . session_picker_view = \"recent\"\ntui.vim_mode_default = true\n\n[projects.\"/tmp/example\"]\ntrust_level = \"trusted\"\n"

  assert_codex_vim_mode_merge \
    "Codex Vim mode merge preserves inline TUI tables" \
    "model = \"gpt-5.5\"\ntui = { theme = \"dark\", vim_mode_default = false, notifications = true }\n\n[projects.\"/tmp/example\"]\ntrust_level = \"trusted\"\n" \
    "model = \"gpt-5.5\"\ntui = { theme = \"dark\", vim_mode_default = true, notifications = true }\n\n[projects.\"/tmp/example\"]\ntrust_level = \"trusted\"\n"

  assert_codex_vim_mode_merge \
    "Codex Vim mode merge adds to existing inline TUI tables" \
    "model = \"gpt-5.5\"\ntui = { theme = \"dark\", notifications = true }\n\n[projects.\"/tmp/example\"]\ntrust_level = \"trusted\"\n" \
    "model = \"gpt-5.5\"\ntui = { theme = \"dark\", notifications = true, vim_mode_default = true }\n\n[projects.\"/tmp/example\"]\ntrust_level = \"trusted\"\n"
}

assert_yaml_query_empty() {
  local path="$1" query="$2" name="$3"
  local value

  value="$(yq -r "$query" "$path" 2>/dev/null || true)"

  if [[ -z "$value" || "$value" == "null" ]]; then
    pass_case "$name"
  else
    fail_case "$name" "expected $query in $path to be empty, got '$value'"
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
  assert_toml_value_equals_yaml "$MISE_TOML" '.tools.node' "$CATALOG" '.tool_versions.runtimes.node' "repo mise config uses catalog-pinned Node.js"
  assert_not_contains "$MISE_TOML" '= "lts"' "repo mise config does not use lts aliases"
  assert_not_contains "$MISE_TOML" '= "latest"' "repo mise config does not use latest aliases"
  assert_not_contains "$CATALOG" "neovim_glibc_legacy: v0.10.4" "catalog no longer preserves legacy neovim compatibility pin"
}

run_install_checks() {
  assert_contains "$LINUX_INSTALLS" "pinned_release_tag: \"{{ tool_versions.github_releases.fzf }}\"" "linux fzf release install uses catalog pin"
  assert_contains "$LINUX_INSTALLS" "- bubblewrap" "linux package install includes bubblewrap for Codex sandboxing"
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
  assert_not_contains "$LINUX_MAIN" "tmux kill-server" "linux tpm install does not kill the user's tmux server"
  assert_contains "$COMMON_MAIN" "version: \"{{ tool_versions.git_tags.superpowers }}\"" "common superpowers clone uses catalog tag"
  assert_contains "$COMMON_MAIN" "install node@{{ tool_versions.runtimes.node }}" "common Linux Node install uses pinned version"
  assert_contains "$COMMON_MAIN" "node@{{ tool_versions.runtimes.node }}" "common Linux Node install uses pinned version"
  assert_contains "$MACOS_DEFAULT_NPM_PACKAGES" "gsd-browser" "mise default npm packages include gsd-browser"
  assert_contains "$COMMON_MAIN" "roles/common/tasks/install_mise_node_global_tools.yml" "common Linux role includes mise node global tools task"
  assert_contains "$MACOS_MAIN" "roles/common/tasks/install_mise_node_global_tools.yml" "macOS role includes mise node global tools task"
  assert_contains "$MISE_NODE_GLOBALS_TASKS" "Install or update gsd-browser via mise npm" "mise node globals task installs gsd-browser"
  assert_contains "$MISE_NODE_GLOBALS_TASKS" "install -g gsd-browser@latest" "mise node globals task uses the gsd-browser npm package"
  assert_contains "$MISE_NODE_GLOBALS_TASKS" 'PATH="$node_bin:$mise_bin_dir:$PATH"' "mise node globals task runs npm with pinned Node first on PATH"
  assert_contains "$COMMON_MAIN" "awk '\$1 == \\\"node\\\" && \$2 == \\\"{{ tool_versions.runtimes.node }}\\\" { found = 1 } END { exit(found ? 0 : 1) }'" "common Linux Node detection uses exact version-column matching"
  assert_contains "$COMMON_MAIN" "bash -s -- latest" "common Claude installer makes latest explicit"
  assert_contains "$COMMON_MAIN" "vim_mode_default = true" "common Codex config defaults composer to Vim mode"
  assert_contains "$MACOS_MAIN" "version: \"{{ tool_versions.git_tags.tpm }}\"" "macOS tpm clone uses catalog tag"
  assert_contains "$MACOS_MAIN" "node@{{ tool_versions.runtimes.node }}" "macOS Node install uses pinned version"
  assert_contains "$MACOS_MAIN" "awk '\$1 == \\\"node\\\" && \$2 == \\\"{{ tool_versions.runtimes.node }}\\\" { found = 1 } END { exit(found ? 0 : 1) }'" "macOS Node detection uses exact version-column matching"
  assert_contains "$MACOS_MAIN" "roles/common/tasks/heal_mise_node_installs.yml" "macOS Node install delegates partial-install heal to the shared task file"
  assert_contains "$HEAL_TASKS" "{{ mise_bin }} ls --installed node" "Node heal enumerates every installed mise node version"
  assert_contains "$HEAL_TASKS" "/bin/{{ item.1 }} --version" "Node heal exec-tests each installed binary instead of stat'ing it"
  assert_contains "$HEAL_TASKS" "{{ mise_bin }} install --force node@{{ item }}" "Node heal force-reinstalls broken versions"
  assert_contains "$MACOS_INSTALLS" "Check installed mise version (macOS)" "macOS install_packages reads the installed mise version"
  assert_yaml_equals "$MACOS_INSTALLS" '.[] | select(.name == "Check installed mise version (macOS)") | .check_mode' "false" "macOS mise pre-upgrade version check runs in check mode"
  assert_contains "$MACOS_INSTALLS" "Upgrade mise if older than catalog pin (macOS)" "macOS install_packages upgrades mise when older than the catalog pin"
  assert_contains "$MACOS_INSTALLS" "tool_versions.runtimes.mise | regex_replace('^v', '')" "macOS install_packages compares mise against the catalog pin"
  assert_yaml_equals "$MACOS_INSTALLS" '.[] | select(.name == "Re-read mise version after upgrade (macOS)") | .check_mode' "false" "macOS mise post-upgrade version check runs in check mode"
  assert_contains "$MACOS_INSTALLS" "Fail if installed mise is still older than catalog pin (macOS)" "macOS install_packages fails loudly if mise stays older than pin"
  assert_yaml_equals "$MACOS_INSTALLS" '.[] | select(.name == "Fail if installed mise is still older than catalog pin (macOS)") | (.when | tostring | contains("not ansible_check_mode"))' "true" "macOS mise hard fail is skipped during check mode"
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
  run_codex_vim_mode_checks
  assert_contains "$COMMON_GITIGNORE" ".repo.yml" "global gitignore ignores .repo.yml"
  assert_contains "$COMMON_MAIN" "- { name: repo-lib.sh, mode: '0644' }" "common install loop includes repo-lib"
  assert_contains "$COMMON_MAIN" "- { name: repo-start, mode: '0755' }" "common install loop includes repo-start"
  assert_contains "$COMMON_MAIN" "- { name: repo-end, mode: '0755' }" "common install loop includes repo-end"
  assert_not_contains "$COMMON_MAIN" "- { name: worktree-lib.sh" "common install loop does not install public worktree-lib"
  assert_not_contains "$COMMON_MAIN" "- { name: worktree-start" "common install loop does not install public worktree-start"
  assert_not_contains "$COMMON_MAIN" "- { name: worktree-delete" "common install loop does not install public worktree-delete"
  assert_not_contains "$COMMON_MAIN" "- { name: worktree-merge" "common install loop does not install public worktree-merge"
  assert_not_contains "$COMMON_MAIN" "- { name: worktree-done" "common install loop does not install public worktree-done"
  assert_contains "$COMMON_MAIN" "Remove legacy public worktree helpers" "common provisioning removes legacy public worktree helpers"
  assert_yaml_query_empty "$COMMON_MAIN" '.[] | select(.file.state == "absent") | .loop[]? | select(. == "cleanup-branches")' "common provisioning does not remove HNP-owned cleanup-branches"
  assert_yaml_query_empty "$COMMON_MAIN" '.[] | select(.file.state == "absent") | .loop[]? | select(. == "git-clean-up")' "common provisioning does not remove HNP-owned git-clean-up"
  assert_yaml_query_empty "$COMMON_MAIN" '.[] | select(.file.state == "absent") | .loop[]? | select(. == "tmux-label-format")' "common provisioning does not remove HNP-owned tmux-label-format"
  assert_yaml_query_empty "$COMMON_MAIN" '.[] | select(.file.state == "absent") | .loop[]? | select(. == ".claude/skills/_clean-up")' "common provisioning does not remove HNP-owned Claude _clean-up"
  assert_yaml_query_empty "$COMMON_MAIN" '.[] | select(.file.state == "absent") | .loop[]? | select(. == ".codex/skills/_clean-up")' "common provisioning does not remove HNP-owned Codex _clean-up"
  assert_yaml_query_empty "$COMMON_MAIN" '.[] | select(.file.state == "absent") | .loop[]? | select(. == ".claude/skills/_monitor-pr")' "common provisioning does not remove HNP-owned Claude _monitor-pr"
  assert_yaml_query_empty "$COMMON_MAIN" '.[] | select(.file.state == "absent") | .loop[]? | select(. == ".codex/skills/_monitor-pr")' "common provisioning does not remove HNP-owned Codex _monitor-pr"
  assert_yaml_query_empty "$COMMON_MAIN" '.[] | select(.file.state == "absent") | .loop[]? | select(. == ".claude/skills/_monitor-github-pr")' "common provisioning does not remove HNP-owned Claude _monitor-github-pr"
  assert_yaml_query_empty "$COMMON_MAIN" '.[] | select(.file.state == "absent") | .loop[]? | select(. == ".codex/skills/_monitor-github-pr")' "common provisioning does not remove HNP-owned Codex _monitor-github-pr"
  assert_yaml_query_empty "$COMMON_MAIN" '.[] | select(.file.state == "absent") | .loop[]? | select(. == ".local/share/skills/_pr-monitor")' "common provisioning does not remove HNP-owned PR monitor runtime"
  assert_yaml_query_empty "$COMMON_MAIN" '.[] | select(.file.state == "absent") | .loop[]? | select(. == ".local/share/skills/_pr-workflow-common")' "common provisioning does not remove HNP-owned PR workflow runtime"
  assert_yaml_query_empty "$COMMON_MAIN" '.[] | select(.file.state == "absent") | .loop[]? | select(. == ".local/share/skills/_pr-github")' "common provisioning does not remove HNP-owned GitHub PR runtime"
  assert_contains "$COMMON_ZSH" "repo-start()" "zsh exposes repo-start wrapper"
  assert_contains "$COMMON_ZSH" "repo-end()" "zsh exposes repo-end wrapper"
  assert_contains "$COMMON_ZSH" "rs()" "zsh exposes rs wrapper"
  assert_contains "$COMMON_ZSH" "re()" "zsh exposes re wrapper"
  assert_not_contains "$COMMON_ZSH" "worktree-start()" "zsh no longer exposes worktree-start wrapper"
  assert_not_contains "$COMMON_ZSH" "worktree-done()" "zsh no longer exposes worktree-done wrapper"
  assert_not_contains "$COMMON_ZSH" "worktree-delete()" "zsh no longer exposes worktree-delete wrapper"
  assert_not_contains "$COMMON_ZSH" "worktree-merge()" "zsh no longer exposes worktree-merge wrapper"
  assert_not_contains "$COMMON_ZSH" "tmux-session-name" "zsh config does not invoke automatic tmux session naming"
  assert_contains "$MACOS_BASH_PROFILE" "repo-start()" "bash profile exposes repo-start wrapper"
  assert_contains "$MACOS_BASH_PROFILE" "repo-end()" "bash profile exposes repo-end wrapper"
  assert_contains "$MACOS_BASH_PROFILE" "rs()" "bash profile exposes rs wrapper"
  assert_contains "$MACOS_BASH_PROFILE" "re()" "bash profile exposes re wrapper"
  assert_not_contains "$MACOS_BASH_PROFILE" "worktree-start()" "bash profile no longer exposes worktree-start wrapper"
  assert_not_contains "$MACOS_BASH_PROFILE" "worktree-done()" "bash profile no longer exposes worktree-done wrapper"
  assert_not_contains "$MACOS_BASH_PROFILE" "worktree-delete()" "bash profile no longer exposes worktree-delete wrapper"
  assert_not_contains "$MACOS_BASH_PROFILE" "worktree-merge()" "bash profile no longer exposes worktree-merge wrapper"
  assert_contains "$CODEX_MAIN_EDIT_HOOK" "repo-start <branch>" "main edit hook names repo-start"
  assert_not_contains "$CODEX_MAIN_EDIT_HOOK" "--use-worktrees" "main edit hook does not tell agents to choose worktree mode"
  assert_not_contains "$CODEX_MAIN_EDIT_HOOK" "--no-worktrees" "main edit hook does not tell agents to choose branch mode"
  assert_contains "$CODEX_WORKTREE_HOOK" "Use repo-start instead." "raw worktree add hook names repo-start"
  assert_contains "$CODEX_WORKTREE_HOOK" "Use repo-end to finish work." "raw worktree remove hook names repo-end"
  assert_not_contains "$CODEX_WORKTREE_HOOK" "worktree-start" "raw worktree hook stops naming worktree-start"
  assert_not_contains "$CODEX_WORKTREE_HOOK" "worktree-delete" "raw worktree hook stops naming worktree-delete"
  assert_not_contains "$CODEX_WORKTREE_HOOK" "worktree-done" "raw worktree hook stops naming worktree-done"
  assert_contains "$TMUX_AGENT_WORKTREE" 'write_pane_option "$pane_id" "@pane-label"' "tmux lifecycle writer caches explicit pane label"
  assert_contains "$TMUX_AGENT_WORKTREE" 'clear_pane_option "$TMUX_PANE" "@pane-label"' "tmux lifecycle clearer removes explicit pane label"
  assert_contains "$TMUX_PANE_LABEL" 'dir_basename "$pane_current_path"' "tmux pane fallback uses cwd basename"
  assert_not_contains "$TMUX_PANE_LABEL" "git_branch_for_path" "tmux pane fallback does not infer branch state"
  assert_contains "$TMUX_WINDOW_LABEL" "strip_host_suffix" "tmux window label strips host suffix"
  assert_contains "$TMUX_SYNC_REMOTE_TITLE" 'pane_title="${pane_title%% | *}"' "remote window title strips host suffix"
  assert_contains "$LINUX_TMUX_CONF" "#{b:pane_current_path} | #{host_short}" "Linux tmux fallback pane label includes host"
  assert_contains "$MACOS_TMUX_CONF" "#{b:pane_current_path} | #{host_short}" "macOS tmux fallback pane label includes host"
  assert_not_contains "$LINUX_TMUX_CONF" "tmux-session-name" "Linux tmux config does not invoke automatic tmux session naming"
  assert_not_contains "$MACOS_TMUX_CONF" "tmux-session-name" "macOS tmux config does not invoke automatic tmux session naming"
  assert_not_contains "$COMMON_MAIN" "Install tmux-session-name script" "common provisioning no longer installs automatic tmux session naming"
  assert_contains "$COMMON_MAIN" "Remove obsolete tmux-session-name helper" "common provisioning removes obsolete tmux session naming helper"
  if [[ ! -e "$TMUX_SESSION_NAME" ]]; then
    pass_case "tmux-session-name helper has been removed"
  else
    fail_case "tmux-session-name helper has been removed" "unexpected file present at $TMUX_SESSION_NAME"
  fi
}

run_renovate_checks() {
  assert_contains "$RENOVATE_CONFIG" "\"extends\": [\"config:recommended\"]" "renovate config extends config:recommended"
  assert_contains "$RENOVATE_CONFIG" "\"minimumReleaseAge\": \"7 days\"" "renovate config uses a seven-day release age"
  assert_contains "$RENOVATE_CONFIG" "\"PR Upkeeper <pr-upkeeper@brianjohn.com>\"" "renovate config ignores PR Upkeeper repair commits"
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
  assert_contains "$INTEGRATION_WORKFLOW" "bash tests/ci-test-inventory.sh" "integration workflow verifies the test inventory"
  assert_contains "$INTEGRATION_WORKFLOW" "bash tests/repo-policy.sh all" "integration workflow runs all repository policy regression checks"
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
  assert_contains "$INTEGRATION_WORKFLOW" 'system_bwrap="/usr/bin/bwrap"' "integration workflow checks the provisioned bubblewrap path"
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

  if [[ ! -e "$CODEX_REVIEW_WORKFLOW" ]]; then
    pass_case "Codex review workflow has been removed"
  else
    fail_case "Codex review workflow has been removed" "unexpected file present at $CODEX_REVIEW_WORKFLOW"
  fi

  assert_not_contains "$WORKFLOWS_DIR" "CLAUDE_CODE_OAUTH_TOKEN" "review workflow no longer references the Claude OAuth token"
  assert_not_contains "$WORKFLOWS_DIR" "@anthropic-ai/claude-code" "review workflow no longer install Claude Code"
  assert_not_contains "$WORKFLOWS_DIR" "claude -p" "review workflow no longer run Claude prompt mode"
  assert_not_contains "$WORKFLOWS_DIR" "bin/codex-pr-review" "review workflow no longer runs the repo-local Codex helper"

  if [[ ! -e "$CODEX_REVIEW_DOC" ]]; then
    pass_case "Codex GitHub review setup doc has been removed"
  else
    fail_case "Codex GitHub review setup doc has been removed" "unexpected file present at $CODEX_REVIEW_DOC"
  fi
}

case "${1:-all}" in
  catalog) run_catalog_checks ;;
  installs) run_install_checks ;;
  codex-vim-mode) run_codex_vim_mode_checks ;;
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
    echo "usage: $0 [catalog|installs|codex-vim-mode|renovate|integration|review|core|all]" >&2
    exit 1
    ;;
esac

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
