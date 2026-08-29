# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "tempfile"
require "tmpdir"

class ConfigureOmniwmSettingsTest < Minitest::Test
  HELPER = File.expand_path("../roles/macos/files/configure-omniwm-settings", __dir__)

  FIXTURE = <<~TOML
    [general]
    ipcEnabled = true

    [[appRules]]
    bundleId = "com.mitchellh.ghostty"
    id = "ghostty-rule"
    minHeight = 400.0
    assignToWorkspace = "7"

    [[appRules]]
    bundleId = "user.unrelated"
    id = "unrelated-rule"
    layout = "float"
    assignToWorkspace = "6"

    [[hotkeys]]
    binding = "Option+1"
    id = "switchWorkspace.0"

    [[hotkeys]]
    binding = "Option+Shift+Left Arrow"
    id = "move.left"

    [[hotkeys]]
    binding = "Control+Option+T"
    id = "toggleScratchpadWindow"

    [[workspaces]]
    id = "workspace-1"
    layoutType = "niri"
    name = "1"
    displayName = "🖥️"

    [workspaces.monitorAssignment]
    type = "main"

    [[workspaces]]
    id = "workspace-2"
    name = "2"
    displayName = "🌐"

    [workspaces.monitorAssignment]
    type = "main"

    [[workspaces]]
    id = "workspace-3"
    name = "3"

    [workspaces.monitorAssignment]
    type = "main"

    [[workspaces]]
    id = "workspace-4"
    name = "4"

    [workspaces.monitorAssignment]
    type = "main"

    [[workspaces]]
    id = "workspace-5"
    name = "5"

    [workspaces.monitorAssignment]
    type = "main"

    [[workspaces]]
    id = "workspace-6"
    name = "6"

    [workspaces.monitorAssignment]
    type = "main"

    [[workspaces]]
    id = "workspace-7"
    name = "7"

    [workspaces.monitorAssignment]
    type = "main"
  TOML

  def with_settings(contents = FIXTURE)
    Dir.mktmpdir do |directory|
      path = File.join(directory, "settings.toml")
      File.write(path, contents)
      yield path
    end
  end

  def run_helper(path, *arguments)
    Open3.capture3(HELPER, path, *arguments)
  end

  def test_default_mode_defers_managed_assignments
    with_settings do |path|
      out, err, status = run_helper(path)
      result = File.read(path)
      ghostty_rule = app_rule(result, "com.mitchellh.ghostty")
      unrelated_rule = app_rule(result, "user.unrelated")

      assert status.success?, err
      assert_equal "changed\n", out
      assert_includes result, 'name = "10"'
      assert_includes result, 'layoutType = "niri"'
      assert_includes result, "binding = \"Unassigned\"\nid = \"move.left\""
      refute_includes ghostty_rule, "assignToWorkspace = "
      assert_includes ghostty_rule, "minHeight = 400.0"
      assert_includes unrelated_rule, 'assignToWorkspace = "6"'
      refute_includes result, 'bundleId = "com.google.Chrome"'
      assert_includes result, "binding = \"Unassigned\"\nid = \"toggleScratchpadWindow\""
    end
  end

  def test_default_mode_is_byte_for_byte_idempotent
    assert_mode_is_idempotent
  end

  def test_active_mode_is_byte_for_byte_idempotent
    assert_mode_is_idempotent("--activate-assignments")
  end

  def test_active_mode_adds_managed_rules_without_duplicates
    with_settings do |path|
      2.times do
        _out, err, status = run_helper(path, "--activate-assignments")
        assert status.success?, err
      end
      result = File.read(path)

      assert_equal 1, result.scan(/^bundleId = "com\.mitchellh\.ghostty"$/).length
      assert_equal 1, result.scan(/^bundleId = "com\.google\.Chrome"$/).length
      assert_equal 16, result.scan(/^assignToWorkspace = /).length
      assert_includes app_rule(result, "com.mitchellh.ghostty"), 'assignToWorkspace = "3"'
      assert_includes app_rule(result, "com.mitchellh.ghostty"), "minHeight = 400.0"
      assert_includes app_rule(result, "com.google.Chrome", "ChatGPT"), 'assignToWorkspace = "4"'
      assert_includes app_rule(result, "user.unrelated"), 'assignToWorkspace = "6"'
      refute_includes result, 'bundleId = "com.apple.finder"'
      refute_includes result, 'bundleId = "com.apple.Photos"'
      result.scan(/^\[\[appRules\]\]\n(.*?)(?=^\[\[|\z)/m).flatten.each do |rule|
        assert_match(/^id = ".+"$/, rule)
      end
    end
  end

  def test_deferred_mode_removes_assignments_after_active_mode
    with_settings do |path|
      _out, err, status = run_helper(path, "--activate-assignments")
      assert status.success?, err

      out, err, status = run_helper(path)
      result = File.read(path)

      assert status.success?, err
      assert_equal "changed\n", out
      assert_equal 1, result.scan(/^assignToWorkspace = /).length
      assert_includes app_rule(result, "user.unrelated"), 'assignToWorkspace = "6"'
      refute_includes app_rule(result, "com.google.Chrome", "ChatGPT"), "assignToWorkspace = "
    end
  end

  def test_finder_and_photos_assignments_are_removed_in_both_modes
    dynamic_rules = FIXTURE + <<~TOML

      [[appRules]]
      bundleId = "com.apple.finder"
      id = "finder-rule"
      layout = "float"
      assignToWorkspace = "10"

      [[appRules]]
      bundleId = "com.apple.Photos"
      id = "photos-rule"
      assignToWorkspace = "10"
    TOML

    [[], ["--activate-assignments"]].each do |arguments|
      with_settings(dynamic_rules) do |path|
        _out, err, status = run_helper(path, *arguments)
        result = File.read(path)
        finder_rule = app_rule(result, "com.apple.finder")

        assert status.success?, err
        refute_includes finder_rule, "assignToWorkspace = "
        assert_includes finder_rule, 'layout = "float"'
        refute_includes result, 'bundleId = "com.apple.Photos"'
      end
    end
  end

  def test_adds_workspaces_eight_through_ten_once
    with_settings do |path|
      2.times do
        _out, err, status = run_helper(path)
        assert status.success?, err
      end
      result = File.read(path)

      workspace_blocks = result.scan(/^\[\[workspaces\]\]\n(.*?)(?=^\[\[|\z)/m).flatten
      %w[8 9 10].each do |name|
        assert_equal 1, result.scan(/^name = "#{name}"$/).length
        block = workspace_blocks.find { |candidate| candidate.match?(/^name = "#{name}"$/) }
        refute_nil block
        assert_includes block, 'layoutType = "niri"'
      end
      assert_includes result, 'id = "4371F67B-B469-470D-89C6-D8FBB5E65BD3"'
      assert_includes result, 'id = "E9D12AB0-EB5E-4B50-98BC-600318BA00FC"'
      assert_includes result, 'id = "1935F5A8-9DCA-4E80-AEE3-48EBBE2E336A"'
    end
  end

  def test_preserves_existing_workspace_id
    existing = FIXTURE + <<~TOML

      [[workspaces]]
      id = "existing-workspace-8"
      name = "8"

      [workspaces.monitorAssignment]
      type = "secondary"
    TOML

    with_settings(existing) do |path|
      _out, err, status = run_helper(path)
      result = File.read(path)

      assert status.success?, err
      assert_includes result, 'id = "existing-workspace-8"'
      refute_includes result, 'id = "4371F67B-B469-470D-89C6-D8FBB5E65BD3"'
    end
  end

  def test_removes_all_workspace_display_names
    with_settings do |path|
      _out, err, status = run_helper(path)

      assert status.success?, err
      refute_match(/^displayName\s*=/, File.read(path))
    end
  end

  def test_malformed_input_is_left_unchanged
    malformed = "[general\nipcEnabled = true\n"

    with_settings(malformed) do |path|
      before = File.binread(path)
      out, _err, status = run_helper(path)

      refute status.success?
      assert_empty out
      assert_equal before, File.binread(path)
    end
  end

  def test_unknown_mode_is_rejected_without_changing_source
    with_settings do |path|
      before = File.binread(path)
      out, err, status = run_helper(path, "--unknown")

      refute status.success?
      assert_empty out
      assert_includes err, "usage: configure-omniwm-settings"
      assert_equal before, File.binread(path)
    end
  end

  def test_invalid_scalar_is_left_unchanged
    malformed = FIXTURE + "\ninvalid scalar\n"

    with_settings(malformed) do |path|
      before = File.binread(path)
      out, err, status = run_helper(path)

      refute status.success?
      assert_empty out
      assert_includes err, "invalid scalar assignment"
      assert_equal before, File.binread(path)
    end
  end

  def test_invalid_string_escape_is_left_unchanged
    assert_invalid_scalar_preserved('bad = "\\q"')
  end

  def test_invalid_array_is_left_unchanged
    assert_invalid_scalar_preserved("bad = [,]")
  end

  private

  def app_rule(document, bundle_id, title_substring = nil)
    rule = document.scan(/^\[\[appRules\]\]\n(.*?)(?=^\[\[|\z)/m).flatten.find do |candidate|
      next false unless candidate.include?(%(bundleId = "#{bundle_id}"))

      if title_substring
        candidate.include?(%(titleSubstring = "#{title_substring}"))
      else
        !candidate.match?(/^titleSubstring = /)
      end
    end
    refute_nil rule, "missing app rule for #{bundle_id}"
    rule
  end

  def assert_mode_is_idempotent(*arguments)
    with_settings do |path|
      _out, err, status = run_helper(path, *arguments)
      assert status.success?, err
      first_result = File.binread(path)

      out, err, status = run_helper(path, *arguments)

      assert status.success?, err
      assert_equal "unchanged\n", out
      assert_equal first_result, File.binread(path)
    end
  end

  def assert_invalid_scalar_preserved(scalar)
    malformed = FIXTURE + "\n#{scalar}\n"

    with_settings(malformed) do |path|
      before = File.binread(path)
      out, err, status = run_helper(path)

      refute status.success?
      assert_empty out
      assert_includes err, "invalid scalar value"
      assert_equal before, File.binread(path)
    end
  end
end
