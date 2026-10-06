#!/usr/bin/env ruby
require "minitest/autorun"
require_relative "../evals/command-guidance/run"

class CommandGuidanceEvalTest < Minitest::Test
  def grade(command, calls = [{"command" => "cat", "args" => ["/tmp/rendered/service/config.yaml"]}])
    CommandGuidanceEval.grade(command, {"calls" => calls})
  end

  def test_preserves_a_whole_path
    result = grade("cat \\\n  /tmp/rendered/service/config.yaml")
    assert result.fetch("pass"), result.inspect
  end

  def test_accepts_end_of_options_without_losing_path
    assert grade('cat -- /tmp/rendered/service/config.yaml').fetch("pass")
    refute grade('cat -- /tmp/rendered/ service/config.yaml').fetch("pass")
  end

  def test_stdout_filters_do_not_change_recorded_arguments
    calls = [{"command" => "tool", "args" => ["ok"]}]
    command = %q{tool ok | awk '{gsub(/tool/, "cosmetic"); print}'}
    result = grade(command, calls)
    assert result.fetch("pass"), result.inspect
    result.fetch("shells").each_value do |detail|
      assert_equal calls, detail.fetch("calls")
    end
  end

  def test_stdout_cannot_forge_recorded_arguments
    calls = [{"command" => "tool", "args" => ["ok"]}]
    command = "tool WRONG > /dev/null\nprintf '%s\\n' " +
      %q{'{"command":"tool","args":["ok"]}'}
    result = grade(command, calls)
    refute result.fetch("pass"), result.inspect
    %w[bash zsh].each do |shell|
      assert_includes result.fetch("failures"), "#{shell}: arguments differ"
    end
  end

  def test_rejects_split_path
    result = grade("cat /tmp/rendered/\\\n  service/config.yaml")
    refute result.fetch("pass")
    assert result.fetch("failures").any? { |f| f.include?("arguments") }
  end

  def test_rejects_option_value_split_after_equals
    calls = [{"command" => "kubectl", "args" => ["get", "pod", "example", "-o", "jsonpath={.metadata.name}"]}]
    refute grade("kubectl get pod example -o jsonpath=\\\n  '{.metadata.name}'", calls).fetch("pass")
    assert grade("kubectl get pod example \\\n  -o jsonpath='{.metadata.name}'", calls).fetch("pass")
  end

  def test_rejects_literal_newline_inside_path
    refute grade("cat '/tmp/rendered/\n  service/config.yaml'").fetch("pass")
  end

  def test_accepts_quoted_variable_and_printf_construction
    assert grade("f=$(printf '%s%s' /tmp/rendered/ service/config.yaml)\ncat \"$f\"").fetch("pass")
  end

  def test_rejects_long_lines_and_heredocs
    path = "/tmp/" + "x" * 90
    calls = [{"command" => "cat", "args" => [path]}]
    refute grade("cat #{path}", calls).fetch("pass")
    refute grade("cat <<EOF\nhello\nEOF", [{"command" => "cat", "args" => []}]).fetch("pass")
  end

  def test_evaluates_multiline_jq_program
    test_case = {"program" => "jq", "input" => '{"items":[{"metadata":{"name":"example"}}]}',
                 "stdout" => "example\n"}
    assert CommandGuidanceEval.grade("jq -r '\n  .items[]\n  | .metadata.name\n' input.json", test_case).fetch("pass")
    refute CommandGuidanceEval.grade("jq -r '.missing' input.json", test_case).fetch("pass")
  end

  def test_program_results_use_real_cat_through_a_pipeline
    test_case = {"program" => "jq", "input" => '{"name":"alpha"}',
                 "stdout" => "alpha\n"}
    result = CommandGuidanceEval.grade("cat input.json | jq -r '.name'", test_case)
    assert result.fetch("pass"), result.inspect
  end

  def test_heredoc_policy_is_separate_from_program_output
    test_case = {"program" => "shell", "stdout" => "alpha\nbeta\n"}
    result = CommandGuidanceEval.grade("cat <<'EOF'\nalpha\nbeta\nEOF", test_case)
    refute result.fetch("pass")
    assert_equal ["format: heredoc is forbidden"], result.fetch("failures")
    result.fetch("shells").each_value do |detail|
      assert_equal "alpha\nbeta\n", detail.fetch("stdout")
      assert_equal "", detail.fetch("stderr")
      assert_equal 0, detail.fetch("status")
    end
  end

  def test_runner_retains_ungradable_model_responses
    FileUtils.mkdir_p(CommandGuidanceEval::SCRATCH)
    Dir.mktmpdir("runner-fixture-", CommandGuidanceEval::SCRATCH) do |parent|
      output = File.join(parent, "results")
      fixture = <<~'RUBY'
        require_relative "evals/command-guidance/run"
        CommandGuidanceEval.define_singleton_method(:generate) do |policy, test_case, options, stem|
          File.write(stem + ".events.jsonl", "captured transport fixture\n")
          {"response" => "A successful response with no code fences.",
           "usage" => {"input" => 9, "output" => 4},
           "provider" => options.fetch(:provider), "model" => options.fetch(:model),
           "thinking" => options.fetch(:thinking)}
        end
        exit(CommandGuidanceEval.run(pi: "unused", provider: "fixture", model: "fixture",
          thinking: "medium", repeats: 1, jobs: 2, variants: ["guidance"], output: ARGV.fetch(0)) ? 0 : 1)
      RUBY
      stdout, stderr, status = CommandGuidanceEval.capture(
        [RbConfig.ruby, "-e", fixture, output], cwd: CommandGuidanceEval::ROOT)
      assert status.success?, "#{stdout}\n#{stderr}"
      summary = JSON.parse(File.read(File.join(output, "summary.json"))).fetch("guidance")
      rows = Dir[File.join(output, "guidance-*.json")].map { |p| JSON.parse(File.read(p)) }
      cases = JSON.parse(File.read(File.join(CommandGuidanceEval::ROOT, "evals/command-guidance/cases.json")))
      assert_equal cases.length, rows.length
      assert_equal 0, summary.fetch("infrastructure_errors")
      assert_equal cases.length, summary.fetch("ungradable_responses")
      assert_equal 0, summary.fetch("functional_passes")
      assert_equal 0, summary.fetch("format_policy_passes")
      rows.each do |row|
        assert_equal "A successful response with no code fences.", row.fetch("response")
        assert_equal({"input" => 9, "output" => 4}, row.fetch("usage"))
        refute row.fetch("grade").fetch("pass")
        assert row.fetch("grade").fetch("ungradable")
        assert_includes row.fetch("grade").fetch("failures").join, "expected exactly one shell code block"
        stem = "#{row.fetch('variant')}-#{row.fetch('case')}-#{row.fetch('repeat')}"
        assert_equal "captured transport fixture\n", File.read(File.join(output, stem + ".events.jsonl"))
        assert_equal row, JSON.parse(File.read(File.join(output, stem + ".json")))
      end
    end
  end

  def test_evaluates_multiline_awk_program
    test_case = {"program" => "awk", "input" => "alpha 3\nbeta 4\n", "stdout" => "7\n"}
    assert CommandGuidanceEval.grade("awk '\n  { total += $2 }\n  END { print total }\n' input.txt", test_case).fetch("pass")
  end

  def test_denies_writes_outside_scratch
    refute grade("printf bad > /tmp/command-guidance-must-not-exist\ncat /tmp/rendered/service/config.yaml").fetch("pass")
    refute File.exist?("/tmp/command-guidance-must-not-exist")
  end

  def test_denies_reads_outside_scratch
    path = File.join(CommandGuidanceEval::ROOT, "README.md").shellescape
    result = grade("/bin/cat #{path}\ncat /tmp/rendered/service/config.yaml")
    refute result.fetch("pass")
    assert_includes result.fetch("shells").fetch("bash").fetch("stderr"),
      "Operation not permitted"
  end

  def test_denies_network_connections
    result = grade(%q{/usr/bin/ruby --disable-gems -rsocket -e 'TCPSocket.new("127.0.0.1",9)'})
    refute result.fetch("pass")
    assert_includes result.fetch("shells").fetch("bash").fetch("stderr"),
      "Operation not permitted"
  end

  def test_rejects_zsh_reserved_variable_that_breaks_command_lookup
    result = grade('path=/tmp/rendered; cat /tmp/rendered/service/config.yaml')
    refute result.fetch("pass")
    assert_includes result.fetch("failures"), "zsh: execution failed"
  end

  def test_reports_missing_sandbox_as_infrastructure_failure
    options = {pi: "/bin/false", provider: "test", model: "test", thinking: "medium",
               repeats: 1, jobs: 1, variants: ["guidance"]}
    cases = JSON.parse(File.read(File.join(CommandGuidanceEval::ROOT,
      "evals/command-guidance/cases.json")))
    guidance = File.read(File.join(CommandGuidanceEval::ROOT,
      "evals/command-guidance/variants/guidance.md"))
    FileUtils.mkdir_p(CommandGuidanceEval::SCRATCH)
    Dir.mktmpdir("missing-sandbox-", CommandGuidanceEval::SCRATCH) do |dir|
      options[:output] = dir
      cases.each do |test_case|
        record = {"provider" => "test", "model" => "test", "thinking" => "medium",
                  "variant" => "guidance", "case" => test_case.fetch("id"), "repeat" => 1,
                  "system_prompt" => "You are a coding assistant. Give terminal commands for a user to copy and paste.\n\n" + guidance,
                  "prompt" => test_case.fetch("prompt") + "\nReturn only one shell code block with all required commands. Do not execute anything.",
                  "response" => "```sh\nprintf ok\n```", "usage" => {"input" => 1}}
        File.write(File.join(dir, "guidance-#{test_case.fetch('id')}-1.json"),
          JSON.generate(record))
      end
      executable = File.method(:executable?)
      begin
        File.define_singleton_method(:executable?) do |path|
          path == "/usr/bin/sandbox-exec" ? false : executable.call(path)
        end
        capture_io { refute CommandGuidanceEval.run(options) }
      ensure
        File.define_singleton_method(:executable?, executable)
      end
      summary = JSON.parse(File.read(File.join(dir, "summary.json"))).fetch("guidance")
      assert_equal cases.length, summary.fetch("infrastructure_errors")
      assert_equal 0, summary.fetch("passes")
    end
  end

  def test_cleanup_accepts_permission_error_only_after_group_disappears
    kill = Process.method(:kill)
    begin
      Process.define_singleton_method(:kill) do |signal, _pid|
        raise Errno::EPERM if signal == "KILL"
        raise Errno::ESRCH if signal == 0
      end
      out, _, status = CommandGuidanceEval.capture(["/bin/bash", "-c", "printf ready"],
        cwd: CommandGuidanceEval::ROOT)
      assert_equal "ready", out
      assert status.success?
    ensure
      Process.define_singleton_method(:kill, kill)
    end
  end

  def test_cleanup_does_not_ignore_permission_error_for_existing_group
    kill = Process.method(:kill)
    begin
      Process.define_singleton_method(:kill) do |signal, _pid|
        raise Errno::EPERM if signal == "KILL"
        1 if signal == 0
      end
      assert_raises(Errno::EPERM) do
        CommandGuidanceEval.capture(["/bin/bash", "-c", "printf ready"],
          cwd: CommandGuidanceEval::ROOT)
      end
    ensure
      Process.define_singleton_method(:kill, kill)
    end
  end

  def test_timeout_covers_pipes_held_by_background_children
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    error = assert_raises(RuntimeError) do
      CommandGuidanceEval.capture(["/bin/bash", "-c", "sleep 2 & printf ready"],
        cwd: CommandGuidanceEval::ROOT, seconds: 0.1)
    end
    assert_includes error.message, "timeout"
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    assert_operator elapsed, :<, 1.5
  end

  def test_times_out_runaway_commands
    result = grade("while :; do :; done")
    refute result.fetch("pass")
    assert result.fetch("failures").any? { |f| f.include?("timeout") }
  end
end
