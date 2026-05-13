#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "tmpdir"

repo_root = File.expand_path("..", __dir__)
hook = File.join(repo_root, "roles/common/files/bin/agent-current-spec-hook")
common_tasks = File.join(repo_root, "roles/common/tasks/main.yml")

GIT_ENV = {
  "GIT_AUTHOR_NAME" => "nmb test",
  "GIT_AUTHOR_EMAIL" => "nmb-test@example.invalid",
  "GIT_COMMITTER_NAME" => "nmb test",
  "GIT_COMMITTER_EMAIL" => "nmb-test@example.invalid"
}.freeze

def fail_case(name, detail)
  warn "FAIL  #{name}"
  warn "      #{detail}"
  exit 1
end

def pass_case(name)
  puts "PASS  #{name}"
end

def task_block(tasks, name)
  start = tasks.index("- name: #{name}") || fail_case(name, "task not found")
  following = tasks.index("\n- name:", start + 1) || tasks.length
  tasks[start...following]
end

def git(*args)
  system(GIT_ENV, "git", *args, out: File::NULL) || raise("git #{args.join(' ')} failed")
end

def make_repo(path)
  git("-c", "init.templateDir=", "init", "-q", path)
  git("-C", path, "commit", "-q", "--allow-empty", "-m", "init")
  FileUtils.mkdir_p(File.join(path, "docs/superpowers/specs"))
  git("-C", path, "add", ".")
  git("-C", path, "commit", "-q", "--allow-empty", "-m", "dirs")
end

def write_fake_tmux(bin_dir, log_path)
  FileUtils.mkdir_p(bin_dir)
  File.write(
    File.join(bin_dir, "tmux"),
    <<~BASH
      #!/usr/bin/env bash
      set -euo pipefail
      if [ "$1" = "show-options" ]; then
        printf '%s\\n' "${TMUX_AGENT_WORKTREE_PATH:-}"
        exit 0
      fi
      printf '%s\\n' "$*" >> #{log_path.dump}
      exit 0
    BASH
  )
  FileUtils.chmod(0o755, File.join(bin_dir, "tmux"))
end

def run_hook(hook, repo, bin_dir, payload, env = {})
  Open3.capture3(
    {
      "PATH" => "#{bin_dir}:#{ENV.fetch("PATH")}",
      "TMUX" => "/tmp/tmux",
      "TMUX_PANE" => "%42"
    }.merge(env),
    hook,
    stdin_data: JSON.generate(payload),
    chdir: repo
  )
end

def assert_sets(name, hook, repo, bin_dir, log_path, payload, expected, env = {})
  FileUtils.rm_f(log_path)
  stdout, stderr, status = run_hook(hook, repo, bin_dir, payload, env)
  fail_case(name, "hook failed: stdout=#{stdout.inspect} stderr=#{stderr.inspect}") unless status.success?
  log = File.exist?(log_path) ? File.read(log_path) : ""
  unless log.include?("set-option -p -t %42 @agent_current_spec_path #{expected}")
    fail_case(name, "expected tmux set-option for #{expected.inspect}, got #{log.inspect}")
  end
  pass_case(name)
end

def assert_ignores(name, hook, repo, bin_dir, log_path, payload, env = {})
  FileUtils.rm_f(log_path)
  stdout, stderr, status = run_hook(hook, repo, bin_dir, payload, env)
  fail_case(name, "hook failed: stdout=#{stdout.inspect} stderr=#{stderr.inspect}") unless status.success?
  log = File.exist?(log_path) ? File.read(log_path) : ""
  fail_case(name, "expected no tmux call, got #{log.inspect}") unless log.empty?
  pass_case(name)
end

Dir.mktmpdir do |tmp|
  repo = File.join(tmp, "repo")
  make_repo(repo)
  spec_a = File.join(repo, "docs/superpowers/specs/2026-05-12-a-design.md")
  spec_b = File.join(repo, "docs/superpowers/specs/2026-05-12-b-design.md")
  flexible_spec = File.join(repo, "docs/superpowers/specs/2026-05-12-flexible.md")
  File.write(spec_a, "# A\n")
  File.write(spec_b, "# B\n")
  File.write(flexible_spec, "# Flexible\n")

  bound_repo = File.join(tmp, "bound-repo")
  make_repo(bound_repo)
  bound_spec = File.join(bound_repo, "docs/superpowers/specs/2026-05-12-bound-design.md")
  File.write(bound_spec, "# Bound\n")

  bin_dir = File.join(tmp, "bin")
  log_path = File.join(tmp, "tmux.log")
  write_fake_tmux(bin_dir, log_path)

  assert_sets(
    "edit payload publishes current spec",
    hook,
    repo,
    bin_dir,
    log_path,
    { "cwd" => repo, "tool_input" => { "file_path" => spec_a } },
    spec_a
  )

  assert_sets(
    "prompt reference publishes current spec",
    hook,
    repo,
    bin_dir,
    log_path,
    { "prompt" => "read docs/superpowers/specs/2026-05-12-a-design.md" },
    spec_a
  )

  assert_sets(
    "prompt reference publishes non-design spec markdown",
    hook,
    repo,
    bin_dir,
    log_path,
    { "prompt" => "read docs/superpowers/specs/2026-05-12-flexible.md" },
    flexible_spec
  )

  assert_sets(
    "prompt reference without cwd uses pane worktree",
    hook,
    repo,
    bin_dir,
    log_path,
    { "prompt" => "read docs/superpowers/specs/2026-05-12-bound-design.md" },
    bound_spec,
    { "TMUX_AGENT_WORKTREE_PATH" => bound_repo }
  )

  assert_sets(
    "prompt reference prefers pane worktree over payload cwd",
    hook,
    repo,
    bin_dir,
    log_path,
    { "cwd" => repo, "prompt" => "read docs/superpowers/specs/2026-05-12-bound-design.md" },
    bound_spec,
    { "TMUX_AGENT_WORKTREE_PATH" => bound_repo }
  )

  assert_sets(
    "stale pane worktree falls back to payload cwd",
    hook,
    repo,
    bin_dir,
    log_path,
    { "cwd" => repo, "prompt" => "read docs/superpowers/specs/2026-05-12-a-design.md" },
    spec_a,
    { "TMUX_AGENT_WORKTREE_PATH" => File.join(tmp, "missing-repo") }
  )

  assert_sets(
    "shell command reference publishes current spec",
    hook,
    repo,
    bin_dir,
    log_path,
    { "cwd" => repo, "tool_input" => { "command" => "sed -n '1,80p' docs/superpowers/specs/2026-05-12-a-design.md" } },
    spec_a
  )

  assert_sets(
    "patch target wins over referenced spec text",
    hook,
    repo,
    bin_dir,
    log_path,
    {
      "cwd" => repo,
      "tool_input" => {
        "command" => [
          "*** Begin Patch",
          "*** Update File: docs/superpowers/specs/2026-05-12-a-design.md",
          "@@",
          "+See docs/superpowers/specs/2026-05-12-b-design.md",
          "*** End Patch"
        ].join("\n")
      }
    },
    spec_a
  )

  assert_sets(
    "patch target publishes non-design spec markdown",
    hook,
    repo,
    bin_dir,
    log_path,
    {
      "cwd" => repo,
      "tool_input" => {
        "command" => [
          "*** Begin Patch",
          "*** Add File: docs/superpowers/specs/2026-05-12-flexible.md",
          "+# Flexible",
          "*** End Patch"
        ].join("\n")
      }
    },
    flexible_spec
  )

  assert_ignores(
    "glob shell command is ignored",
    hook,
    repo,
    bin_dir,
    log_path,
    {
      "cwd" => repo,
      "tool_input" => {
        "command" => "ls docs/superpowers/specs/*.md"
      }
    }
  )

  assert_ignores(
    "non-spec patch reference is ignored",
    hook,
    repo,
    bin_dir,
    log_path,
    {
      "cwd" => repo,
      "tool_input" => {
        "command" => [
          "*** Begin Patch",
          "*** Update File: README.md",
          "@@",
          "+See docs/superpowers/specs/2026-05-12-a-design.md",
          "*** End Patch"
        ].join("\n")
      }
    }
  )

  assert_ignores(
    "prefixed relative spec reference is ignored",
    hook,
    repo,
    bin_dir,
    log_path,
    { "cwd" => repo, "prompt" => "read tmp/docs/superpowers/specs/2026-05-12-a-design.md" }
  )

  assert_ignores(
    "multi-spec prompt is ignored",
    hook,
    repo,
    bin_dir,
    log_path,
    { "prompt" => "compare #{spec_a} and #{spec_b}" }
  )

  assert_ignores(
    "non-spec prompt is ignored",
    hook,
    repo,
    bin_dir,
    log_path,
    { "prompt" => "read README.md" }
  )
end

tasks = File.read(common_tasks)
unless tasks.include?("matcher='Bash|Edit|MultiEdit|Read|Write'")
  fail_case("Claude PostToolUse invokes current-spec hook for reads", "missing expanded Claude matcher")
end
pass_case("Claude PostToolUse invokes current-spec hook for reads")

unless tasks.include?("matcher='Bash|apply_patch|Edit|MultiEdit|Read|Write|shell_command'")
  fail_case("Codex PostToolUse invokes current-spec hook for shell reads", "missing expanded Codex matcher")
end
pass_case("Codex PostToolUse invokes current-spec hook for shell reads")

unless tasks.scan(/UserPromptSubmit.*?agent-current-spec-hook/m).length >= 2
  fail_case("prompt submit invokes current-spec hook for both agents", "missing Claude/Codex UserPromptSubmit registration")
end
pass_case("prompt submit invokes current-spec hook for both agents")

[
  "Register PostToolUse Edit|MultiEdit|Write hook for publishing current spec path",
  "Register UserPromptSubmit hook for publishing current spec path",
  "Merge managed Codex current spec hook into ~/.codex/hooks.json",
  "Merge managed Codex current spec prompt hook into ~/.codex/hooks.json"
].each do |name|
  block = task_block(tasks, name)
  fail_case("#{name} canonicalizes duplicates", "short-circuits before cleanup") if block.include?("exit 0")
  unless block.include?("map(.hooks = ((.hooks // []) | map(select(.type != \"command\" or .command != $cmd))))")
    fail_case("#{name} canonicalizes duplicates", "does not preserve sibling hooks while filtering")
  end
  unless block.include?("jq -e --slurp '.[0] == .[1]'")
    fail_case("#{name} canonicalizes duplicates", "does not compare normalized JSON before writing")
  end
  unless block.include?("[ ! -s ")
    fail_case("#{name} canonicalizes duplicates", "does not seed empty config files")
  end
  pass_case("#{name} canonicalizes duplicates")
end
