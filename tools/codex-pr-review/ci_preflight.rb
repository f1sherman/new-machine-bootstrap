#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"

AUTH_PATH = File.join(Dir.home, ".codex", "auth.json")
AUTH_URL = "https://auth.openai.com"
DEFAULT_CLIENT_VERSION = "0.122.0"

def fail_with(message, detail = nil)
  warn(message)
  warn(detail) if detail && !detail.empty?
  exit(1)
end

def capture_command(*command)
  Open3.capture3(*command)
rescue Errno::ENOENT => e
  fail_with("Missing required command: #{command.first}", e.message)
end

def codex_client_version
  stdout, stderr, status = capture_command("codex", "--version")
  fail_with("Unable to detect Codex CLI version", stderr) unless status.success?

  stdout[/\d+\.\d+\.\d+/] || DEFAULT_CLIENT_VERSION
end

def probe(url, failure_message)
  stdout, stderr, status = capture_command(
    "curl", "--silent", "--show-error", "--location",
    "--output", "/dev/null", "--write-out", "%{http_code}",
    "--max-time", ENV.fetch("CODEX_CI_PREFLIGHT_TIMEOUT", "20"),
    url
  )

  fail_with(failure_message, stderr) unless status.success? && stdout.strip != "000"
end

fail_with("Codex auth cache missing at #{AUTH_PATH}") unless File.file?(AUTH_PATH)

stdout, stderr, status = capture_command("codex", "login", "status")
fail_with("Codex login status failed", stderr.empty? ? stdout : stderr) unless status.success?

probe(AUTH_URL, "Codex CI preflight failed: auth.openai.com not reachable through configured proxy")

# Probe the cheap HTTPS models endpoint before the real websocket-backed exec path.
probe(
  "https://chatgpt.com/backend-api/codex/models?client_version=#{ENV.fetch("CODEX_CI_CLIENT_VERSION", codex_client_version)}",
  "Codex CI preflight failed: chatgpt.com Codex models endpoint not reachable through configured proxy"
)

puts("Codex CI preflight passed")
