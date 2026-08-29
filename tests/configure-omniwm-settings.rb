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

    [[appRules]]
    bundleId = "user.unrelated"
    id = "unrelated-rule"
    layout = "float"

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

  def run_helper(path)
    Open3.capture3(HELPER, path)
  end

  def test_reconciles_workspaces_hotkeys_and_rules
    with_settings do |path|
      out, err, status = run_helper(path)
      result = File.read(path)

      assert status.success?, err
      assert_equal "changed\n", out
      assert_includes result, 'name = "10"'
      assert_includes result, "binding = \"Unassigned\"\nid = \"move.left\""
      assert_includes result, 'assignToWorkspace = "3"'
      assert_includes result, 'bundleId = "user.unrelated"'
      assert_includes result, 'minHeight = 400.0'
      assert_includes result, "binding = \"Unassigned\"\nid = \"toggleScratchpadWindow\""
    end
  end

  def test_second_run_is_byte_for_byte_idempotent
    with_settings do |path|
      _out, err, status = run_helper(path)
      assert status.success?, err
      first_result = File.binread(path)

      out, err, status = run_helper(path)

      assert status.success?, err
      assert_equal "unchanged\n", out
      assert_equal first_result, File.binread(path)
    end
  end

  def test_does_not_duplicate_managed_application_rules
    with_settings do |path|
      2.times do
        _out, err, status = run_helper(path)
        assert status.success?, err
      end
      result = File.read(path)

      assert_equal 1, result.scan(/^bundleId = "com\.mitchellh\.ghostty"$/).length
      assert_equal 1, result.scan(/^bundleId = "com\.google\.Chrome"$/).length
      assert_equal 17, result.scan(/^assignToWorkspace = /).length
      result.scan(/^\[\[appRules\]\]\n(.*?)(?=^\[\[|\z)/m).flatten.each do |rule|
        assert_match(/^id = ".+"$/, rule)
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

      %w[8 9 10].each do |name|
        assert_equal 1, result.scan(/^name = "#{name}"$/).length
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
end
