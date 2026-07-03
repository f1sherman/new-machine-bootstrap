#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "tmpdir"

repo_root = File.expand_path("..", __dir__)
helper = File.join(repo_root, "roles/common/files/bin/pi-codex-subscription-defaults")

abort "FAIL  missing helper #{helper}" unless File.executable?(helper)

Dir.mktmpdir("pi-codex-defaults") do |home|
  settings_dir = File.join(home, ".pi/agent")
  settings_path = File.join(settings_dir, "settings.json")
  FileUtils.mkdir_p(settings_dir)
  File.write(settings_path, JSON.pretty_generate({
    "defaultProvider" => "openai",
    "defaultModel" => "gpt-5.5",
    "theme" => "managed-dark"
  }))

  env = { "HOME" => home }
  output, status = Open3.capture2e(env, helper)
  abort "FAIL  helper failed:\n#{output}" unless status.success?
  abort "FAIL  helper should report changed, got #{output.inspect}" unless output.strip == "changed"

  settings = JSON.parse(File.read(settings_path))
  abort "FAIL  defaultProvider was not repaired" unless settings["defaultProvider"] == "openai-codex"
  abort "FAIL  defaultModel was not repaired" unless settings["defaultModel"] == "gpt-5.5"
  abort "FAIL  unrelated settings were not preserved" unless settings["theme"] == "managed-dark"

  mode = File.stat(settings_path).mode & 0o777
  abort "FAIL  settings file mode should be 0600, got #{mode.to_s(8)}" unless mode == 0o600

  output, status = Open3.capture2e(env, helper)
  abort "FAIL  second helper run failed:\n#{output}" unless status.success?
  abort "FAIL  second helper run should be unchanged, got #{output.inspect}" unless output.strip == "unchanged"

  File.chmod(0o644, settings_path)
  output, status = Open3.capture2e(env, helper)
  abort "FAIL  mode repair helper run failed:\n#{output}" unless status.success?
  abort "FAIL  mode repair should report changed, got #{output.inspect}" unless output.strip == "changed"

  mode = File.stat(settings_path).mode & 0o777
  abort "FAIL  mode repair should restore 0600, got #{mode.to_s(8)}" unless mode == 0o600
end

puts "PASS  Pi defaults use OpenAI Codex subscription auth"
