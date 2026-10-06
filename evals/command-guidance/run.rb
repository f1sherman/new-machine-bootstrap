#!/usr/bin/env ruby
require "optparse"
require_relative "grader"

module CommandGuidanceEval
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
    response_from(out, {"thinking" => options.fetch(:thinking),
                        "system_prompt" => system, "prompt" => prompt})
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
