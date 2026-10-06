#!/usr/bin/env ruby
require "json"
require "open3"
require "optparse"
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

  def self.generate(variant, test_case, options, stem)
    system = "You are a coding assistant. Give terminal commands for a user to copy and paste.\n\n" + variant
    prompt = test_case.fetch("prompt") + "\nReturn only one shell code block with all required commands. Do not execute anything."
    argv = [options.fetch(:pi), "--print", "--mode", "json", "--no-session", "--no-tools",
            "--no-extensions", "--no-skills", "--no-context-files", "--no-prompt-templates",
            "--no-themes", "--no-approve", "--offline", "--provider", options.fetch(:provider),
            "--model", options.fetch(:model), "--thinking", options.fetch(:thinking),
            "--system-prompt", system, prompt]
    out, err, status = capture(argv, cwd: SCRATCH, seconds: 180)
    File.write(stem + ".events.jsonl", out)
    File.write(stem + ".stderr", err)
    raise "Pi process failed: #{err}" unless status.success?
    events = out.split("\n").reject(&:empty?).map { |line| JSON.parse(line) }
    message = events.reverse.find { |e| e["type"] == "message_end" && e.dig("message", "role") == "assistant" }&.fetch("message")
    raise "missing successful assistant message" unless message && message["stopReason"] == "stop" && events.any? { |e| e["type"] == "agent_settled" }
    text = message.fetch("content").select { |c| c["type"] == "text" }.map { |c| c.fetch("text") }.join
    {"response" => text, "usage" => message.fetch("usage"), "provider" => message.fetch("provider"),
     "model" => message.fetch("model"), "thinking" => options.fetch(:thinking),
     "system_prompt" => system, "prompt" => prompt}
  end

  def self.run(options)
    cases = JSON.parse(File.read(File.join(__dir__, "cases.json")))
    variants = Dir[File.join(__dir__, "variants", "*.md")].sort.to_h { |path| [File.basename(path, ".md"), File.read(path)] }
    variants.select! { |name, _| options[:variants].include?(name) } if options[:variants]
    raise "no variants selected" if variants.empty?
    FileUtils.mkdir_p(SCRATCH)
    output = File.expand_path(options.fetch(:output))
    FileUtils.mkdir_p(output)
    queue = Queue.new
    jobs = variants.keys.product(cases, (1..options.fetch(:repeats)).to_a).shuffle(random: Random.new(631))
    jobs.each { |job| queue << job }
    results = []
    lock = Mutex.new
    workers = Array.new(options.fetch(:jobs)) do
      Thread.new do
        loop do
          name, test_case, repeat = queue.pop(true)
          stem = File.join(output, "#{name}-#{test_case.fetch('id')}-#{repeat}")
          begin
            if File.exist?(stem + ".json")
              result = JSON.parse(File.read(stem + ".json"))
              raise "cached configuration differs; use a new output directory" unless result.values_at("provider", "model", "thinking", "system_prompt", "prompt") ==
                [options.fetch(:provider), options.fetch(:model), options.fetch(:thinking),
                 "You are a coding assistant. Give terminal commands for a user to copy and paste.\n\n" + variants.fetch(name),
                 test_case.fetch("prompt") + "\nReturn only one shell code block with all required commands. Do not execute anything."]
            else
              result = generate(variants.fetch(name), test_case, options, stem)
              result.merge!("variant" => name, "case" => test_case.fetch("id"), "repeat" => repeat)
            end
            begin
              result["grade"] = grade(command_from(result.fetch("response")), test_case)
            rescue RuntimeError => e
              result["grade"] = {"pass" => false, "ungradable" => true, "failures" => [e.message]}
            end
            File.write(stem + ".json", JSON.pretty_generate(result) + "\n")
            lock.synchronize do
              results << result
              puts "#{name} #{test_case.fetch('id')} #{repeat}: #{result.dig('grade', 'pass') ? 'PASS' : result.dig('grade', 'failures').join('; ')}"
              $stdout.flush
            end
          rescue StandardError => e
            lock.synchronize { results << {"variant" => name, "case" => test_case.fetch("id"), "repeat" => repeat, "infrastructure_error" => e.message}; warn "#{name} #{test_case.fetch('id')}: #{e.message}" }
          end
        rescue ThreadError
          break
        end
      end
    end
    workers.each(&:join)
    summary = variants.to_h do |name, text|
      rows = results.select { |r| r["variant"] == name }
      usage = rows.filter_map { |r| r["usage"] }
      [name, {"words" => text.split.length, "characters" => text.length, "runs" => rows.length,
              "passes" => rows.count { |r| r.dig("grade", "pass") },
              "functional_passes" => rows.count { |r| r.dig("grade", "shells")&.keys&.sort == %w[bash zsh] && r.dig("grade", "failures").reject { |f| f.start_with?("format:") }.empty? },
              "format_policy_passes" => rows.count { |r| r.dig("grade", "shells") && r.dig("grade", "failures").grep(/^format:/).empty? },
              "ungradable_responses" => rows.count { |r| r.dig("grade", "ungradable") },
              "infrastructure_errors" => rows.count { |r| r["infrastructure_error"] },
              "mean_input_tokens" => usage.empty? ? nil : usage.sum { |u| u.fetch("input") + u.fetch("cacheRead", 0) + u.fetch("cacheWrite", 0) }.fdiv(usage.length),
              "cost" => usage.sum { |u| u.dig("cost", "total") || 0 },
              "failures" => rows.reject { |r| r.dig("grade", "pass") }.map { |r| r.slice("case", "repeat", "grade", "infrastructure_error") }}]
    end
    File.write(File.join(output, "summary.json"), JSON.pretty_generate(summary) + "\n")
    puts JSON.pretty_generate(summary.transform_values { |s| s.reject { |k, _| k == "failures" } })
    results.none? { |r| r["infrastructure_error"] }
  end
end

if $PROGRAM_NAME == __FILE__
  options = {pi: "pi", provider: ENV.fetch("PI_PROVIDER", "openai"), model: ENV.fetch("PI_MODEL", "gpt-6.1-sol"),
             thinking: "medium", repeats: 3, jobs: 4, output: File.join(CommandGuidanceEval::SCRATCH, "regression")}
  OptionParser.new do |parser|
    parser.banner = "Usage: ruby evals/command-guidance/run.rb [options]"
    parser.on("--pi PATH") { |v| options[:pi] = v }
    parser.on("--provider NAME") { |v| options[:provider] = v }
    parser.on("--model NAME") { |v| options[:model] = v }
    parser.on("--thinking LEVEL") { |v| options[:thinking] = v }
    parser.on("--variants LIST", Array) { |v| options[:variants] = v }
    parser.on("--repeats N", Integer) { |v| options[:repeats] = v }
    parser.on("--jobs N", Integer) { |v| options[:jobs] = v }
    parser.on("--output PATH") { |v| options[:output] = v }
  end.parse!
  abort "repeats and jobs must be positive" unless options[:repeats].positive? && options[:jobs].positive?
  exit(CommandGuidanceEval.run(options) ? 0 : 1)
end
