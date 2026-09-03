# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "tempfile"
require "tmpdir"

class RecoverOmniwmWorkspacesTest < Minitest::Test
  HELPER = File.expand_path("../roles/macos/files/recover-omniwm-workspaces", __dir__)
  RULES = File.expand_path("../roles/macos/files/omniwm-workspace-rules.json", __dir__)

  def setup
    @directory = Dir.mktmpdir
    @state_path = File.join(@directory, "state.json")
    @calls_path = File.join(@directory, "calls.jsonl")
    @lock_path = File.join(@directory, "recovery.lock")
    @fake_ctl = File.join(@directory, "omniwmctl")
    File.write(@fake_ctl, fake_omniwmctl)
    FileUtils.chmod(0o755, @fake_ctl)
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def test_default_rules_path_uses_deployed_share_directory
    deployed_rules = File.join(@directory, ".local/share/omniwm/omniwm-workspace-rules.json")
    FileUtils.mkdir_p(File.dirname(deployed_rules))
    FileUtils.cp(RULES, deployed_rules)
    write_state(
      "windows" => [window("ow_chrome", "com.google.Chrome", "ChatGPT", 1)],
      "targets" => {"ow_chrome" => 4}
    )

    out, err, status = run_helper_without_rules

    assert status.success?, err
    assert_match(/moved=1/, out)
  end

  def test_minimum_wait_is_measured_from_helper_launch
    write_state(
      "pingDelay" => 1.0,
      "windows" => [window("ow_chrome", "com.google.Chrome", "ChatGPT", 4)]
    )

    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    _out, err, status = run_helper(
      environment: {
        "OMNIWM_RECOVERY_MIN_WAIT_SECONDS" => "1.0",
        "OMNIWM_RECOVERY_POLL_SECONDS" => "0",
        "OMNIWM_RECOVERY_TIMEOUT_SECONDS" => "3"
      }
    )
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at

    assert status.success?, err
    assert_operator elapsed, :<, 1.7
  end

  def test_retries_ping_and_waits_for_two_equal_window_snapshots
    changing = [
      window("ow_first", "com.google.Chrome", "First", 1),
      window("ow_second", "com.brave.Browser", "Second", 1)
    ]
    stable = [
      window("ow_first", "com.google.Chrome", "First", 1),
      window("ow_second", "com.brave.Browser", "Second", 1),
      window("ow_third", "com.todoist.mac.Todoist", "Third", 1)
    ]
    write_state(
      "pingFailures" => 2,
      "querySequences" => [changing, stable, stable],
      "targets" => {"ow_first" => 4, "ow_second" => 5, "ow_third" => 1}
    )

    out, err, status = run_helper

    assert status.success?, err
    calls = read_calls
    assert_equal 3, calls.count { |call| call == ["ping"] }
    assert_operator calls.count { |call| call[0, 2] == ["query", "windows"] }, :>=, 4
    assert_includes calls, ["rule", "apply", "--window", "ow_first"]
    assert_includes calls, ["rule", "apply", "--window", "ow_second"]
    refute_includes calls, ["rule", "apply", "--window", "ow_third"]
    assert_match(/moved=2/, out)
  end

  def test_applies_bundle_and_safari_profile_rules_to_exact_live_ids
    windows = [
      window("ow_todoist", "com.todoist.mac.Todoist", "Todoist", 8),
      window("ow_personal", "com.apple.Safari", "Personal — Bank", 1),
      window("ow_development", "com.apple.Safari", "Development — Start Page", 1),
      window("ow_work", "com.apple.Safari", "Work — Slack", 1)
    ]
    write_state(
      "windows" => windows,
      "targets" => {
        "ow_todoist" => 1,
        "ow_personal" => 2,
        "ow_development" => 3,
        "ow_work" => 9
      }
    )

    out, err, status = run_helper

    assert status.success?, err
    applied = read_calls.select { |call| call[0, 2] == ["rule", "apply"] }
    assert_equal [
      ["rule", "apply", "--window", "ow_development"],
      ["rule", "apply", "--window", "ow_personal"],
      ["rule", "apply", "--window", "ow_todoist"],
      ["rule", "apply", "--window", "ow_work"]
    ], applied.sort_by(&:last)
    refute_match(/Bank|Slack|Start Page/, out)
    assert_match(/moved=4/, out)
  end

  def test_skips_unknown_titleless_and_ambiguous_windows
    custom_rules = File.join(@directory, "ambiguous-rules.json")
    File.write(custom_rules, JSON.generate([
      {"bundleId" => "com.apple.Safari", "titleRegex" => "^Personal", "workspace" => "2"},
      {"bundleId" => "com.apple.Safari", "titleRegex" => "^Personal —", "workspace" => "3"}
    ]))
    windows = [
      window("ow_unknown", "user.unknown", "Unknown", 1),
      window("ow_titleless", "com.apple.Safari", nil, 1),
      window("ow_titleless_chrome", "com.google.Chrome", nil, 1),
      window("ow_ambiguous", "com.apple.Safari", "Personal — Bank", 1)
    ]
    write_state("windows" => windows)

    out, err, status = run_helper("--rules", custom_rules)

    assert status.success?, err
    refute read_calls.any? { |call| call[0, 2] == ["rule", "apply"] }
    assert_match(/skipped=4/, out)
  end

  def test_check_reports_drift_without_applying_rules
    write_state(
      "windows" => [window("ow_chrome", "com.google.Chrome", "ChatGPT", 1)],
      "targets" => {"ow_chrome" => 4}
    )

    out, err, status = run_helper("--check")

    assert status.success?, err
    refute read_calls.any? { |call| call[0, 2] == ["rule", "apply"] }
    assert_match(/check id=ow_chrome bundle=com\.google\.Chrome selector=bundle workspace=1->4/, out)
    assert_match(/pending=1/, out)
  end

  def test_already_correct_windows_do_not_apply_rules
    write_state(
      "windows" => [window("ow_brave", "com.brave.Browser", "Shop", 5)],
      "targets" => {"ow_brave" => 5}
    )

    out, err, status = run_helper

    assert status.success?, err
    refute read_calls.any? { |call| call[0, 2] == ["rule", "apply"] }
    assert_match(/unchanged=1/, out)
  end

  def test_apply_failure_is_reported_and_later_windows_continue
    windows = [
      window("ow_chrome", "com.google.Chrome", "ChatGPT", 1),
      window("ow_brave", "com.brave.Browser", "Shop", 1)
    ]
    write_state(
      "windows" => windows,
      "targets" => {"ow_chrome" => 4, "ow_brave" => 5},
      "failApply" => ["ow_chrome"]
    )

    out, err, status = run_helper

    assert status.success?, err
    calls = read_calls
    assert_includes calls, ["rule", "apply", "--window", "ow_chrome"]
    assert_includes calls, ["rule", "apply", "--window", "ow_brave"]
    assert_match(/failed id=ow_chrome bundle=com\.google\.Chrome selector=bundle workspace=1->4/, err)
    assert_match(/failed=1/, out)
    assert_match(/moved=1/, out)
  end

  def test_malformed_query_fails_without_applying_rules
    write_state("malformedQuery" => true)

    _out, err, status = run_helper

    refute status.success?
    assert_match(/invalid OmniWM window response/, err)
    refute read_calls.any? { |call| call[0, 2] == ["rule", "apply"] }
  end

  def test_non_object_window_fails_without_a_stack_trace_or_rule_application
    write_state("windows" => [nil])

    _out, err, status = run_helper

    refute status.success?
    assert_equal "invalid OmniWM window response\n", err
    refute read_calls.any? { |call| call[0, 2] == ["rule", "apply"] }
  end

  def test_ipc_timeout_fails_without_query_or_apply
    write_state("pingAlwaysFails" => true)

    _out, err, status = run_helper(
      environment: {
        "OMNIWM_RECOVERY_TIMEOUT_SECONDS" => "0.02",
        "OMNIWM_RECOVERY_POLL_SECONDS" => "0.001"
      }
    )

    refute status.success?
    assert_match(/Timed out waiting for OmniWM IPC/, err)
    refute read_calls.any? { |call| call[0] == "query" || call[0, 2] == ["rule", "apply"] }
  end

  def test_held_lock_exits_without_querying_omniwm
    write_state("windows" => [])
    File.open(@lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
      lock.flock(File::LOCK_EX)
      out, err, status = run_helper

      assert status.success?, err
      assert_match(/already running/, out)
      assert_empty read_calls
    end
  end

  def test_second_run_over_corrected_state_is_idempotent
    write_state(
      "windows" => [window("ow_personal", "com.apple.Safari", "Personal — Mail", 1)],
      "targets" => {"ow_personal" => 2}
    )

    first_out, first_err, first_status = run_helper
    first_apply_count = read_calls.count { |call| call[0, 2] == ["rule", "apply"] }
    second_out, second_err, second_status = run_helper
    second_apply_count = read_calls.count { |call| call[0, 2] == ["rule", "apply"] }

    assert first_status.success?, first_err
    assert second_status.success?, second_err
    assert_equal 1, first_apply_count
    assert_equal first_apply_count, second_apply_count
    assert_match(/moved=1/, first_out)
    assert_match(/unchanged=1/, second_out)
  end

  def test_invalid_manifests_fail_before_querying_omniwm
    invalid_manifests = {
      "top-level object" => {},
      "unknown key" => [{"bundleId" => "com.google.Chrome", "workspace" => "4", "extra" => true}],
      "missing selector" => [{"workspace" => "4"}],
      "invalid workspace" => [{"bundleId" => "com.google.Chrome", "workspace" => "11"}],
      "invalid regex type" => [{"bundleId" => "com.apple.Safari", "titleRegex" => false, "workspace" => "2"}],
      "invalid regex" => [{"bundleId" => "com.apple.Safari", "titleRegex" => "[", "workspace" => "2"}],
      "unsafe regex string" => [
        {"bundleId" => "com.apple.Safari", "titleRegex" => '^Personal\\s+"', "workspace" => "2"}
      ],
      "duplicate selector" => [
        {"bundleId" => "com.google.Chrome", "workspace" => "4"},
        {"bundleId" => "com.google.Chrome", "workspace" => "5"}
      ]
    }
    write_state("windows" => [])

    invalid_manifests.each do |name, manifest|
      invalid_rules = File.join(@directory, "#{name.tr(' ', '-')}.json")
      File.write(invalid_rules, JSON.generate(manifest))
      _out, err, status = run_helper("--rules", invalid_rules)

      refute status.success?, name
      refute_empty err, name
    end
    assert_empty read_calls
  end

  def test_unknown_argument_fails_before_querying_omniwm
    write_state("windows" => [])

    _out, err, status = run_helper("--unexpected")

    refute status.success?
    assert_match(/unknown argument: --unexpected/, err)
    refute_match(/recover-omniwm-workspaces:\d+/, err)
    assert_empty read_calls
  end

  def test_final_query_failure_is_fatal_after_rule_application
    write_state(
      "windows" => [window("ow_chrome", "com.google.Chrome", "ChatGPT", 1)],
      "targets" => {"ow_chrome" => 4},
      "malformedQueryAfter" => 3
    )

    _out, err, status = run_helper

    refute status.success?
    assert_match(/invalid OmniWM window response/, err)
    assert_includes read_calls, ["rule", "apply", "--window", "ow_chrome"]
  end

  private

  def run_helper(*arguments, environment: {})
    env = {
      "OMNIWMCTL" => @fake_ctl,
      "FAKE_OMNIWM_STATE" => @state_path,
      "FAKE_OMNIWM_CALLS" => @calls_path,
      "OMNIWM_RECOVERY_LOCK" => @lock_path,
      "OMNIWM_RECOVERY_MIN_WAIT_SECONDS" => "0",
      "OMNIWM_RECOVERY_STABLE_SECONDS" => "0",
      "OMNIWM_RECOVERY_POLL_SECONDS" => "0",
      "OMNIWM_RECOVERY_TIMEOUT_SECONDS" => "1",
      "OMNIWM_RECOVERY_NOTIFY" => "0"
    }.merge(environment)
    Open3.capture3(env, HELPER, "--rules", RULES, *arguments)
  end

  def run_helper_without_rules
    env = {
      "HOME" => @directory,
      "OMNIWMCTL" => @fake_ctl,
      "FAKE_OMNIWM_STATE" => @state_path,
      "FAKE_OMNIWM_CALLS" => @calls_path,
      "OMNIWM_RECOVERY_LOCK" => @lock_path,
      "OMNIWM_RECOVERY_MIN_WAIT_SECONDS" => "0",
      "OMNIWM_RECOVERY_STABLE_SECONDS" => "0",
      "OMNIWM_RECOVERY_POLL_SECONDS" => "0",
      "OMNIWM_RECOVERY_TIMEOUT_SECONDS" => "1",
      "OMNIWM_RECOVERY_NOTIFY" => "0"
    }
    Open3.capture3(env, HELPER)
  end

  def write_state(state)
    File.write(@state_path, JSON.generate(state))
  end

  def read_calls
    return [] unless File.exist?(@calls_path)

    File.readlines(@calls_path, chomp: true).map { |line| JSON.parse(line) }
  end

  def window(id, bundle_id, title, workspace)
    {
      "id" => id,
      "app" => {"bundleId" => bundle_id},
      "title" => title,
      "workspace" => {"number" => workspace}
    }
  end

  def fake_omniwmctl
    <<~'RUBY'
      #!/usr/bin/env ruby
      require "json"

      state_path = ENV.fetch("FAKE_OMNIWM_STATE")
      calls_path = ENV.fetch("FAKE_OMNIWM_CALLS")
      arguments = ARGV.dup
      File.open(calls_path, "a") { |file| file.puts(JSON.generate(arguments)) }

      output = nil
      exit_code = 0
      File.open(state_path, File::RDWR) do |file|
        file.flock(File::LOCK_EX)
        state = JSON.parse(file.read)
        state["pingCount"] ||= 0
        state["queryCount"] ||= 0

        case arguments
        when ["ping"]
          sleep(state["pingDelay"]) if state["pingDelay"]
          state["pingCount"] += 1
          if state["pingAlwaysFails"] || state["pingCount"] <= state.fetch("pingFailures", 0)
            warn "not ready"
            exit_code = 1
          else
            output = "pong\n"
          end
        when ["query", "windows", "--format", "json"]
          state["queryCount"] += 1
          if state["malformedQuery"] ||
              (state["malformedQueryAfter"] && state["queryCount"] >= state["malformedQueryAfter"])
            output = "not-json\n"
          else
            sequences = state["querySequences"]
            windows = if sequences
              sequences.fetch([state["queryCount"] - 1, sequences.length - 1].min)
            else
              state.fetch("windows", [])
            end
            output = JSON.generate(
              "ok" => true,
              "result" => {"payload" => {"windows" => windows}}
            ) + "\n"
          end
        else
          if arguments[0, 3] == ["rule", "apply", "--window"] && arguments.length == 4
            id = arguments.fetch(3)
            if state.fetch("failApply", []).include?(id)
              warn "apply failed"
              exit_code = 1
            else
              target = state.fetch("targets", {})[id]
              state.fetch("windows", []).each do |window|
                window["workspace"]["number"] = target if window["id"] == id && target
              end
              if state["querySequences"] && target
                state["querySequences"].each do |windows|
                  windows.each do |window|
                    window["workspace"]["number"] = target if window["id"] == id
                  end
                end
              end
              output = "applied\n"
            end
          else
            warn "unexpected arguments: #{arguments.inspect}"
            exit_code = 2
          end
        end

        file.rewind
        file.write(JSON.generate(state))
        file.truncate(file.pos)
      end

      print output if output
      exit exit_code
    RUBY
  end
end
