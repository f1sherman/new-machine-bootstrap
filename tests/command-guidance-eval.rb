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

  def test_evaluates_multiline_awk_program
    test_case = {"program" => "awk", "input" => "alpha 3\nbeta 4\n", "stdout" => "7\n"}
    assert CommandGuidanceEval.grade("awk '\n  { total += $2 }\n  END { print total }\n' input.txt", test_case).fetch("pass")
  end

  def test_rejects_helper_files_when_case_forbids_them
    test_case = {"program" => "shell", "no_files" => true,
                 "input" => "", "stdout" => "alpha\nbeta\n"}
    assert CommandGuidanceEval.grade("printf '%s\\n' alpha beta", test_case).fetch("pass")
    command = "printf '%s\\n' alpha beta > out; /usr/bin/awk '{print}' out"
    refute CommandGuidanceEval.grade(command, test_case).fetch("pass")
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
               set: "development", repeats: 1, jobs: 1, variants: ["compact-portable"]}
    cases = JSON.parse(File.read(File.join(CommandGuidanceEval::ROOT,
      "evals/command-guidance/cases.json"))).fetch("development")
    guidance = File.read(File.join(CommandGuidanceEval::ROOT,
      "evals/command-guidance/variants/compact-portable.md"))
    FileUtils.mkdir_p(CommandGuidanceEval::SCRATCH)
    Dir.mktmpdir("missing-sandbox-", CommandGuidanceEval::SCRATCH) do |dir|
      options[:output] = dir
      cases.each do |test_case|
        record = {"provider" => "test", "model" => "test", "thinking" => "medium",
                  "variant" => "compact-portable", "case" => test_case.fetch("id"), "repeat" => 1,
                  "system_prompt" => "You are a coding assistant. Give terminal commands for a user to copy and paste.\n\n" + guidance,
                  "prompt" => test_case.fetch("prompt") + "\nReturn only one shell code block with all required commands. Do not execute anything.",
                  "response" => "```sh\nprintf ok\n```", "usage" => {"input" => 1}}
        File.write(File.join(dir, "compact-portable-#{test_case.fetch('id')}-1.json"),
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
      summary = JSON.parse(File.read(File.join(dir, "summary.json"))).fetch("compact-portable")
      assert_equal cases.length, summary.fetch("infrastructure_errors")
      assert_equal 0, summary.fetch("passes")
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
