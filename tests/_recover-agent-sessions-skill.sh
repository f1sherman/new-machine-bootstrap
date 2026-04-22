#!/usr/bin/env ruby
# frozen_string_literal: true

require "pathname"
require "shellwords"

REPO_ROOT = Pathname.new(`git -C #{Shellwords.escape(__dir__)} rev-parse --show-toplevel`.strip)
COMMON_SKILL = REPO_ROOT.join("roles/common/files/config/skills/common/_recover-agent-sessions/SKILL.md")
CLAUDE_SKILL_DIR = REPO_ROOT.join("roles/common/files/config/skills/claude/_recover-agent-sessions")
CODEX_SKILL_DIR = REPO_ROOT.join("roles/common/files/config/skills/codex/_recover-agent-sessions")
HELPER = REPO_ROOT.join("roles/common/files/bin/_recover-agent-sessions")
MAIN_YML = REPO_ROOT.join("roles/common/tasks/main.yml")

pass = 0
fail = 0

def pass_case(label, pass_count)
  puts "PASS  #{label}"
  pass_count + 1
end

def fail_case(label, detail, fail_count)
  warn "FAIL  #{label}"
  warn "      #{detail}"
  fail_count + 1
end

def assert_exists(path, label, pass_count, fail_count)
  if path.exist?
    [pass_case(label, pass_count), fail_count]
  else
    [pass_count, fail_case(label, "missing path: #{path}", fail_count)]
  end
end

def assert_missing(path, label, pass_count, fail_count)
  if !path.exist?
    [pass_case(label, pass_count), fail_count]
  else
    [pass_count, fail_case(label, "unexpected path exists: #{path}", fail_count)]
  end
end

def assert_contains(path, needle, label, pass_count, fail_count)
  unless path.file?
    return [pass_count, fail_case(label, "missing file: #{path}", fail_count)]
  end

  if path.read.include?(needle)
    [pass_case(label, pass_count), fail_count]
  else
    [pass_count, fail_case(label, "missing needle #{needle.inspect} in #{path}", fail_count)]
  end
end

pass, fail = assert_exists(COMMON_SKILL, "shared _recover-agent-sessions skill exists", pass, fail)
pass, fail = assert_missing(CLAUDE_SKILL_DIR, "no Claude-specific _recover-agent-sessions override", pass, fail)
pass, fail = assert_missing(CODEX_SKILL_DIR, "no Codex-specific _recover-agent-sessions override", pass, fail)
pass, fail = assert_exists(HELPER, "shared _recover-agent-sessions helper exists", pass, fail)

pass, fail = assert_contains(COMMON_SKILL, "name: _recover-agent-sessions", "skill uses canonical name", pass, fail)
pass, fail = assert_contains(COMMON_SKILL, "default 24h", "skill documents the default window", pass, fail)
pass, fail = assert_contains(COMMON_SKILL, "codex-yolo", "skill references codex-yolo", pass, fail)
pass, fail = assert_contains(COMMON_SKILL, "claude-yolo", "skill references claude-yolo", pass, fail)
pass, fail = assert_contains(MAIN_YML, "Install _recover-agent-sessions helper", "Ansible installs the helper", pass, fail)
pass, fail = assert_contains(MAIN_YML, ".local/bin/_recover-agent-sessions", "Ansible installs into ~/.local/bin", pass, fail)
pass, fail = assert_contains(MAIN_YML, ".local/bin/_find-agent-sessions", "Ansible removes the old helper install", pass, fail)
pass, fail = assert_contains(MAIN_YML, ".claude/skills/_find-agent-sessions", "Ansible removes the old Claude skill install", pass, fail)
pass, fail = assert_contains(MAIN_YML, ".codex/skills/_find-agent-sessions", "Ansible removes the old Codex skill install", pass, fail)

puts
puts "#{pass} passed, #{fail} failed"
exit(fail.zero? ? 0 : 1)
