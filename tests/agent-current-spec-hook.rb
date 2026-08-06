#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "tmpdir"

repo_root = File.expand_path("..", __dir__)
hook = File.join(repo_root, "roles/common/files/bin/agent-current-spec-hook")

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

def git(*args)
  system(GIT_ENV, "git", *args, out: File::NULL) || raise("git #{args.join(' ')} failed")
end

def make_repo(path)
  git("-c", "init.templateDir=", "init", "-q", path)
  git("-C", path, "commit", "-q", "--allow-empty", "-m", "init")
end

def write_fake_tmux(bin_dir, log_path)
  FileUtils.mkdir_p(bin_dir)
  File.write(File.join(bin_dir, "tmux"), <<~BASH)
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "$1" = "show-options" ]; then
      printf '%s\\n' "${TMUX_AGENT_WORKTREE_PATH:-}"
      exit 0
    fi
    printf '%s\\n' "$*" >> #{log_path.dump}
  BASH
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
    fail_case(name, "expected #{expected.inspect}, got #{log.inspect}")
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
  bound_repo = File.join(tmp, "bound-repo")
  nested_worktree = File.join(repo, ".worktrees/current-worktree")
  [repo, bound_repo, nested_worktree].each { |path| make_repo(path) }

  spec = File.join(repo, "docs/superpowers/specs/current.md")
  FileUtils.mkdir_p(File.dirname(spec))
  File.write(spec, "# Current\n")

  configured_directory = "docs/.solution-designs"
  configured_spec = File.join(repo, configured_directory, "configured.md")
  FileUtils.mkdir_p(File.dirname(configured_spec))
  File.write(configured_spec, "# Configured\n")
  config_home = File.join(tmp, "config")
  FileUtils.mkdir_p(File.join(config_home, "new-machine-bootstrap"))
  File.write(File.join(config_home, "new-machine-bootstrap/spec-directory"), "#{configured_directory}\n")
  configured_env = { "XDG_CONFIG_HOME" => config_home }

  bin_dir = File.join(tmp, "bin")
  log_path = File.join(tmp, "tmux.log")
  write_fake_tmux(bin_dir, log_path)

  assert_sets(
    "stale pane worktree falls back to payload repository",
    hook, repo, bin_dir, log_path,
    { "cwd" => repo, "tool_input" => { "file_path" => "docs/superpowers/specs/current.md" } },
    spec,
    { "TMUX_AGENT_WORKTREE_PATH" => File.join(tmp, "missing-repo") }
  )

  assert_sets(
    "absolute target uses its own repository instead of pane binding",
    hook, repo, bin_dir, log_path,
    { "cwd" => repo, "tool_input" => { "file_path" => configured_spec } },
    configured_spec,
    configured_env.merge("TMUX_AGENT_WORKTREE_PATH" => bound_repo)
  )

  assert_sets(
    "relative patch target resolves against pane worktree",
    hook, repo, bin_dir, log_path,
    {
      "cwd" => repo,
      "tool_input" => { "command" => "*** Begin Patch\n*** Add File: docs/superpowers/specs/bound.md\n*** End Patch" }
    },
    File.join(bound_repo, "docs/superpowers/specs/bound.md"),
    { "TMUX_AGENT_WORKTREE_PATH" => bound_repo }
  )

  assert_sets(
    "current worktree-prefixed target resolves to current worktree",
    hook, repo, bin_dir, log_path,
    {
      "cwd" => repo,
      "tool_input" => { "command" => "*** Begin Patch\n*** Add File: .worktrees/current-worktree/docs/superpowers/specs/prefixed.md\n*** End Patch" }
    },
    File.join(nested_worktree, "docs/superpowers/specs/prefixed.md"),
    { "TMUX_AGENT_WORKTREE_PATH" => nested_worktree }
  )

  assert_sets(
    "configured directory resolves within current worktree",
    hook, repo, bin_dir, log_path,
    {
      "cwd" => repo,
      "tool_input" => { "command" => "*** Begin Patch\n*** Add File: .worktrees/current-worktree/docs/.solution-designs/prefixed.md\n*** End Patch" }
    },
    File.join(nested_worktree, "docs/.solution-designs/prefixed.md"),
    configured_env.merge("TMUX_AGENT_WORKTREE_PATH" => nested_worktree)
  )

  assert_ignores(
    "other worktree-prefixed target is not published",
    hook, repo, bin_dir, log_path,
    {
      "cwd" => repo,
      "tool_input" => { "command" => "*** Begin Patch\n*** Add File: .worktrees/other/docs/superpowers/specs/prefixed.md\n*** End Patch" }
    },
    { "TMUX_AGENT_WORKTREE_PATH" => nested_worktree }
  )
end
