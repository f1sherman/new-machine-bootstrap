#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "open3"
require "tmpdir"

repo_root = File.expand_path("..", __dir__)
script = ENV.fetch(
  "TMUX_SPEC_CURRENT_UNDER_TEST",
  File.join(repo_root, "roles/common/files/bin/tmux-spec-current")
)
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

def run(env, *command)
  Open3.capture3(env, *command)
end

def git(*args)
  system(GIT_ENV, "git", *args, out: File::NULL) || raise("git #{args.join(' ')} failed")
end

def make_repo(path, specs)
  git("-c", "init.templateDir=", "init", "-q", path)
  git("-C", path, "commit", "-q", "--allow-empty", "-m", "init")
  spec_dir = File.join(path, "docs/superpowers/specs")
  FileUtils.mkdir_p(spec_dir)
  specs.each do |name|
    File.write(File.join(spec_dir, name), "# #{name}\n")
  end
  git("-C", path, "add", ".")
  git("-C", path, "commit", "-q", "-m", "specs")
end

def fake_tmux(path, pane_path:, option: "", worktree_path: "")
  FileUtils.mkdir_p(path)
  File.write(
    File.join(path, "tmux"),
    <<~BASH
      #!/usr/bin/env bash
      set -euo pipefail
      case "${1:-}" in
        show-options)
          requested="${@: -1}"
          case "$requested" in
            @agent_current_spec_path) printf '%s' #{option.dump} ;;
            @agent_worktree_path) printf '%s' #{worktree_path.dump} ;;
          esac
          ;;
        display-message)
          printf '%s' #{pane_path.dump}
          ;;
        *)
          exit 1
          ;;
      esac
    BASH
  )
  FileUtils.chmod(0o755, File.join(path, "tmux"))
end

Dir.mktmpdir do |tmp|
  multi_repo = File.join(tmp, "multi")
  make_repo(
    multi_repo,
    [
      "2026-05-01-old-design.md",
      "2026-05-02-new-design.md"
    ]
  )

  fake_tmux(File.join(tmp, "bin-option"), pane_path: multi_repo, option: "docs/superpowers/specs/2026-05-01-old-design.md")
  stdout, stderr, status = run(
    {
      "TMUX" => "/tmp/tmux",
      "TMUX_PANE" => "%31",
      "TMUX_SPEC_TMUX_BIN" => File.join(tmp, "bin-option/tmux")
    },
    script
  )
  expected = File.join(multi_repo, "docs/superpowers/specs/2026-05-01-old-design.md")
  unless status.success? && stdout.strip == expected
    fail_case("pane option wins", "expected #{expected.inspect}, got stdout=#{stdout.inspect} stderr=#{stderr.inspect}")
  end
  pass_case("pane option wins")

  single_repo = File.join(tmp, "single")
  make_repo(single_repo, ["2026-05-03-only.md"])
  fake_tmux(File.join(tmp, "bin-single"), pane_path: single_repo)
  stdout, stderr, status = run(
    {
      "TMUX" => "/tmp/tmux",
      "TMUX_PANE" => "%32",
      "TMUX_SPEC_TMUX_BIN" => File.join(tmp, "bin-single/tmux")
    },
    script
  )
  expected = File.join(single_repo, "docs/superpowers/specs/2026-05-03-only.md")
  unless status.success? && stdout.strip == expected
    fail_case("single-spec fallback resolves", "expected #{expected.inspect}, got stdout=#{stdout.inspect} stderr=#{stderr.inspect}")
  end
  pass_case("single-spec fallback resolves")

  pane_repo = File.join(tmp, "pane-main")
  make_repo(pane_repo, ["2026-05-04-main.md"])
  bound_repo = File.join(tmp, "bound-worktree")
  make_repo(bound_repo, ["2026-05-04-bound.md"])
  fake_tmux(File.join(tmp, "bin-bound"), pane_path: pane_repo, worktree_path: bound_repo)
  stdout, stderr, status = run(
    {
      "TMUX" => "/tmp/tmux",
      "TMUX_PANE" => "%34",
      "TMUX_SPEC_TMUX_BIN" => File.join(tmp, "bin-bound/tmux")
    },
    script
  )
  expected = File.join(bound_repo, "docs/superpowers/specs/2026-05-04-bound.md")
  unless status.success? && stdout.strip == expected
    fail_case("bound worktree fallback wins over pane cwd", "expected #{expected.inspect}, got stdout=#{stdout.inspect} stderr=#{stderr.inspect}")
  end
  pass_case("bound worktree fallback wins over pane cwd")

  fake_tmux(File.join(tmp, "bin-multi"), pane_path: multi_repo)
  stdout, stderr, status = run(
    {
      "TMUX" => "/tmp/tmux",
      "TMUX_PANE" => "%33",
      "TMUX_SPEC_TMUX_BIN" => File.join(tmp, "bin-multi/tmux")
    },
    script
  )
  fail_case("multi-spec fallback is ambiguous", "expected failure, got stdout=#{stdout.inspect}") if status.success?
  unless stderr.include?("ambiguous current spec")
    fail_case("multi-spec fallback is ambiguous", "expected ambiguous-current-spec error, got stderr=#{stderr.inspect}")
  end
  pass_case("multi-spec fallback is ambiguous")
end
