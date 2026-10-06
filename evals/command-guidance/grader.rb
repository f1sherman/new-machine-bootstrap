#!/usr/bin/env ruby
require "json"
require "open3"
require "fileutils"
require "tmpdir"
require "timeout"
require "shellwords"

module CommandGuidanceEval
  class InfrastructureError < StandardError; end

  ROOT = File.expand_path("../..", __dir__)
  SCRATCH = File.join(ROOT, "tmp", "command-guidance")
  HOME = "/home/eval"
  STUB = <<~'RUBY'
    #!/usr/bin/ruby --disable-gems
    require "json"
    record = JSON.generate({"command" => File.basename($0), "args" => ARGV})
    File.open(File.expand_path("../calls.jsonl", __dir__), "a") do |file|
      file.puts(record)
    end
    puts record
  RUBY

  def self.capture(argv, cwd:, env: {}, seconds: 10)
    out = err = ""
    status = nil
    Open3.popen3(env, *argv, chdir: cwd, pgroup: true) do |stdin, stdout, stderr, wait|
      stdin.close
      readers = [Thread.new { stdout.read }, Thread.new { stderr.read }]
      begin
        Timeout.timeout(seconds) do
          status = wait.value
          out, err = readers.map(&:value)
        end
      rescue Timeout::Error
        raise "timeout after #{seconds}s"
      ensure
        begin
          Process.kill("KILL", -wait.pid)
        rescue Errno::ESRCH
          # The process group has already exited.
        rescue Errno::EPERM => error
          begin
            Process.kill(0, -wait.pid)
          rescue Errno::ESRCH
            # Ignore the denial only when the group no longer exists.
          else
            raise error
          end
        ensure
          readers.each(&:kill)
          readers.each(&:join)
        end
      end
    end
    [out, err, status]
  end

  def self.sandbox_profile(directory, program: false)
    # Default-deny: only scratch and system runtimes are readable. No network.
    paths = [directory, "/usr", "/bin", "/System", "/Library", "/opt/homebrew"]
    reads = paths.map { |path| "(subpath #{path.to_json})" }.join(" ")
    executables = %w[/usr/bin/env /usr/bin/ruby /usr/bin/uname /usr/bin/awk /bin/bash /bin/zsh /opt/homebrew/bin/jq]
    executables << "/bin/cat" if program
    execs = executables.map { |path| "(literal #{File.realpath(path).to_json})" }.join(" ")
    "(version 1)(deny default)(allow process-fork)(allow process-info*)" \
      "(allow process-exec #{execs} (subpath #{directory.to_json}))(allow sysctl-read)" \
      "(allow mach-lookup)(allow file-read-metadata)" \
      "(allow file-read* #{reads} (literal \"/\") (literal \"/dev/null\"))" \
      "(allow file-write* (subpath #{directory.to_json}) (literal \"/dev/null\"))"
  end

  def self.normalize(call, test_case)
    args = call.fetch("args").dup
    args.shift if call.fetch("command") == "cat" && args.first == "--"
    test_case.fetch("options", {}).each do |canonical, aliases|
      args = args.flat_map do |arg|
        option = ([canonical] + aliases).find { |name| arg.start_with?(name + "=") }
        if option
          [canonical, arg.delete_prefix(option + "=")]
        elsif aliases.include?(arg)
          [canonical]
        else
          [arg]
        end
      end
    end
    {"command" => call.fetch("command"), "args" => args}
  end

  def self.grade(command, test_case)
    raise InfrastructureError, "macOS sandbox-exec is required; refusing unsandboxed execution" unless File.executable?("/usr/bin/sandbox-exec")
    failures = []
    failures << "format: line exceeds 80 characters" if command.lines.any? { |line| line.chomp.length > 80 }
    failures << "format: heredoc is forbidden" if command.include?("<<")
    failures << "format: empty command" if command.strip.empty?
    FileUtils.mkdir_p(SCRATCH)
    details = {}
    Dir.mktmpdir("grade-", SCRATCH) do |dir|
      bin = File.join(dir, "bin")
      FileUtils.mkdir_p(bin)
      (test_case["program"] ? [] : %w[cat kubectl curl tool]).each do |name|
        File.write(File.join(bin, name), STUB)
        File.chmod(0o755, File.join(bin, name))
      end
      if %w[jq awk].include?(test_case["program"])
        filename = test_case["program"] == "jq" ? "input.json" : "input.txt"
        File.write(File.join(dir, filename), test_case.fetch("input"))
      end
      # env -i also removes API credentials and shell startup variables.
      %w[bash zsh].each do |shell|
        begin
          records = File.join(dir, "calls.jsonl")
          File.write(records, "")
          args = ["/usr/bin/sandbox-exec", "-p", sandbox_profile(dir, program: !!test_case["program"]),
                  "/usr/bin/env", "-i", "HOME=#{HOME}", "TMPDIR=#{dir}", "TMPPREFIX=#{dir}/zsh", "PATH=#{bin}:/opt/homebrew/bin:/usr/bin:/bin",
                  "/bin/#{shell}", "-f", "-eu", "-c", command]
          out, err, status = capture(args, cwd: dir, seconds: 3)
          details[shell] = {"stdout" => out, "stderr" => err, "status" => status.exitstatus, "signal" => status.termsig}
          failures << "#{shell}: execution failed" unless status.success? && err.empty?
          if test_case["program"]
            failures << "#{shell}: program result differs" unless out == test_case.fetch("stdout")
          else
            recorded = File.readlines(records).map { |line| JSON.parse(line) }
            details[shell]["calls"] = recorded
            calls = recorded.map { |call| normalize(call, test_case) }
            expected = test_case.fetch("calls").map { |call| normalize(call, test_case) }
            failures << "#{shell}: arguments differ" unless calls == expected
          end
        rescue JSON::ParserError, KeyError => e
          failures << "#{shell}: invalid argument capture: #{e.message}"
        rescue RuntimeError => e
          failures << "#{shell}: #{e.message}"
        end
      end
    end
    {"pass" => failures.empty?, "failures" => failures, "shells" => details}
  end

  def self.command_from(text)
    blocks = text.scan(/```(?:bash|sh|shell|zsh)?\s*\n(.*?)```/m).flatten
    raise "expected exactly one shell code block, got #{blocks.length}" unless blocks.length == 1
    blocks.first
  end

  def self.response_from(stream, settings)
    events = stream.lines.reject { |line| line.strip.empty? }.map { |line| JSON.parse(line) }
    raise InfrastructureError, "missing settled agent stream" unless events.any? { |e| e["type"] == "agent_settled" }
    if events.any? { |e| e["type"].to_s.start_with?("tool_execution_") }
      raise InfrastructureError, "unexpected tool execution in prompt-only trial"
    end
    system = events.find { |e| e["type"] == "message_end" && e.dig("message", "role") == "system" }&.fetch("message")
    user = events.find { |e| e["type"] == "message_end" && e.dig("message", "role") == "user" }&.fetch("message")
    user_text = user&.fetch("content")&.select { |part| part["type"] == "text" }&.map { |part| part.fetch("text") }&.join
    unless system&.dig("sections", "preamble") == settings.fetch("system_prompt") && user_text == settings.fetch("prompt")
      raise InfrastructureError, "captured system or user prompt differs from staged case"
    end
    messages = events.select { |e| e["type"] == "message_end" && e.dig("message", "role") == "assistant" }
    message = messages.last&.fetch("message")
    unless message && message["stopReason"] == "stop"
      raise InfrastructureError, "missing successful assistant message"
    end
    if message.fetch("content").any? { |part| part["type"] == "toolCall" }
      raise InfrastructureError, "unexpected assistant tool call in prompt-only trial"
    end
    usage = message.fetch("usage")
    %w[input output cacheRead cacheWrite].each do |key|
      value = usage.fetch(key, %w[input output].include?(key) ? nil : 0)
      unless value.is_a?(Numeric) && value.finite? && value >= 0
        raise InfrastructureError, "invalid usage: #{key}"
      end
    end
    text = message.fetch("content").select { |part| part["type"] == "text" }.map { |part| part.fetch("text") }.join
    {"response" => text, "usage" => usage, "provider" => message.fetch("provider"),
     "model" => message.fetch("model"), "thinking" => settings.fetch("thinking"),
     "system_prompt" => settings.fetch("system_prompt"), "prompt" => settings.fetch("prompt")}
  end

  def self.evaluate(request)
    result = response_from(request.fetch("events"), request.fetch("settings"))
    begin
      result["grade"] = grade(command_from(result.fetch("response")), request.fetch("test_case"))
    rescue RuntimeError => error
      result["grade"] = {"pass" => false, "ungradable" => true, "failures" => [error.message]}
    end
    result
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    request = JSON.parse(File.read(ARGV.fetch(0)))
    puts JSON.generate(CommandGuidanceEval.evaluate(request))
  rescue StandardError => error
    puts JSON.generate({"infrastructure_error" => "#{error.class}: #{error.message}"})
    exit 1
  end
end
