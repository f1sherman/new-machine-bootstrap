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
  system("git", *args, out: File::NULL) || raise("git #{args.join(' ')} failed")
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

def fake_tmux(path, pane_path:, option: "")
  FileUtils.mkdir_p(path)
  File.write(
    File.join(path, "tmux"),
    <<~BASH
      #!/usr/bin/env bash
      set -euo pipefail
      case "${1:-}" in
        show-options)
          printf '%s' #{option.dump}
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
  make_repo(single_repo, ["2026-05-03-only-design.md"])
  fake_tmux(File.join(tmp, "bin-single"), pane_path: single_repo)
  stdout, stderr, status = run(
    {
      "TMUX" => "/tmp/tmux",
      "TMUX_PANE" => "%32",
      "TMUX_SPEC_TMUX_BIN" => File.join(tmp, "bin-single/tmux")
    },
    script
  )
  expected = File.join(single_repo, "docs/superpowers/specs/2026-05-03-only-design.md")
  unless status.success? && stdout.strip == expected
    fail_case("single-spec fallback resolves", "expected #{expected.inspect}, got stdout=#{stdout.inspect} stderr=#{stderr.inspect}")
  end
  pass_case("single-spec fallback resolves")

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
