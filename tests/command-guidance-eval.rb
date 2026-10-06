#!/usr/bin/env ruby
require "minitest/autorun"
require_relative "../evals/command-guidance/grader"

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

  def native_grade(response, settled: true, tool_event: false,
                   usage: {"input" => 9, "output" => 4}, actual_prompt: "fixture")
    message = {"role" => "assistant", "stopReason" => "stop",
               "content" => [{"type" => "text", "text" => response}],
               "usage" => usage, "provider" => "fixture", "model" => "fixture"}
    events = [{"type" => "message_end", "message" => {"role" => "system",
                 "sections" => {"preamble" => "fixture", "cwd" => "fixture"}}},
              {"type" => "message_end", "message" => {"role" => "user",
                 "content" => [{"type" => "text", "text" => actual_prompt}]}},
              {"type" => "message_end", "message" => message}]
    events << {"type" => "tool_execution_start", "toolName" => "bash"} if tool_event
    events << {"type" => "agent_settled"} if settled
    request = {"events" => events.map { |e| JSON.generate(e) }.join("\n"),
               "test_case" => {"calls" => [{"command" => "cat",
                 "args" => ["/tmp/rendered/service/config.yaml"]}]},
               "settings" => {"provider" => "fixture", "model" => "fixture",
                 "thinking" => "medium", "system_prompt" => "fixture", "prompt" => "fixture"}}
    FileUtils.mkdir_p(CommandGuidanceEval::SCRATCH)
    Dir.mktmpdir("native-fixture-", CommandGuidanceEval::SCRATCH) do |dir|
      input = File.join(dir, "request.json")
      File.write(input, JSON.generate(request))
      stdout, stderr, status = CommandGuidanceEval.capture(
        [RbConfig.ruby, File.join(CommandGuidanceEval::ROOT,
          "evals/command-guidance/grader.rb"), input], cwd: dir)
      yield stdout, stderr, status, request
    end
  end

  def test_native_stream_entry_point_grades_actual_arguments
    native_grade("```sh\ncat /tmp/rendered/service/config.yaml\n```") do |out, err, status|
      assert status.success?, err
      refute_empty out, "native grader entry point must emit an assessment"
      result = JSON.parse(out)
      assert result.fetch("grade").fetch("pass"), result.inspect
      result.fetch("grade").fetch("shells").each_value do |detail|
        assert_equal [{"command" => "cat", "args" => ["/tmp/rendered/service/config.yaml"]}], detail.fetch("calls")
      end
    end
  end

  def test_native_stream_entry_point_retains_ungradable_response_and_usage
    native_grade("No code fences.") do |out, err, status|
      assert status.success?, err
      refute_empty out, "native grader entry point must retain model evidence"
      result = JSON.parse(out)
      assert_equal "No code fences.", result.fetch("response")
      assert_equal({"input" => 9, "output" => 4}, result.fetch("usage"))
      assert result.fetch("grade").fetch("ungradable")
      refute result.fetch("grade").fetch("pass")
    end
  end

  def test_native_stream_entry_point_rejects_unsettled_trials
    native_grade("```sh\ncat /tmp/rendered/service/config.yaml\n```", settled: false) do |out, _, status|
      refute status.success?, "an incomplete stream must not produce a passing trial"
      assert_match(/settled/, JSON.parse(out).fetch("infrastructure_error"))
    end
  end

  def test_native_stream_entry_point_rejects_tool_using_trials
    native_grade("```sh\ncat /tmp/rendered/service/config.yaml\n```", tool_event: true) do |out, _, status|
      refute status.success?, "tool use violates isolated response generation"
      assert_match(/tool/, JSON.parse(out).fetch("infrastructure_error"))
    end
  end

  def test_native_stream_entry_point_rejects_invalid_usage
    [{"output" => 4}, {"input" => -1, "output" => 4}, {"input" => 0, "output" => 4}].each do |usage|
      native_grade("```sh\ncat /tmp/rendered/service/config.yaml\n```", usage: usage) do |out, _, status|
        refute status.success?, "missing or invalid usage must not become a measured trial"
        assert_match(/usage/, JSON.parse(out).fetch("infrastructure_error"))
      end
    end
  end

  def test_native_stream_entry_point_rejects_mismatched_prompt
    native_grade("```sh\ncat /tmp/rendered/service/config.yaml\n```", actual_prompt: "different task") do |out, _, status|
      refute status.success?, "a response to a different task must not be graded as this case"
      assert_match(/prompt/, JSON.parse(out).fetch("infrastructure_error"))
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
    native_grade("```sh\ncat /tmp/rendered/service/config.yaml\n```") do |_, _, _, request|
      executable = File.method(:executable?)
      begin
        File.define_singleton_method(:executable?) do |path|
          path == "/usr/bin/sandbox-exec" ? false : executable.call(path)
        end
        assert_raises(CommandGuidanceEval::InfrastructureError) { CommandGuidanceEval.evaluate(request) }
      ensure
        File.define_singleton_method(:executable?, executable)
      end
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
