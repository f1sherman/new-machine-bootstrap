# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "open3"
require "tempfile"
require "tmpdir"

class ConfigureOmniwmSettingsTest < Minitest::Test
  HELPER = File.expand_path("../roles/macos/files/configure-omniwm-settings", __dir__)
  RULES = File.expand_path("../roles/macos/files/omniwm-workspace-rules.json", __dir__)

  EXPECTED_ASSIGNMENTS = {
    ["com.todoist.mac.Todoist", nil] => "1",
    ["com.apple.Safari", "^Personal —"] => "2",
    ["com.mitchellh.ghostty", nil] => "3",
    ["com.apple.Safari", "^Development —"] => "3",
    ["com.openai.codex", nil] => "4",
    ["com.google.Chrome", nil] => "4",
    ["com.brave.Browser", nil] => "5",
    ["com.getcardpointers.app", nil] => "5",
    ["com.apple.MobileSMS", nil] => "6",
    ["io.robbie.HomeAssistant", nil] => "7",
    ["com.apple.iCal", nil] => "8",
    ["com.apple.Safari", "^Work —"] => "9",
    ["com.tinyspeck.slackmacgap", nil] => "9",
    ["com.bitwarden.desktop", nil] => "10",
    ["com.TechSmith.Snagit", nil] => "10",
    ["com.backblaze.Backblaze", nil] => "10",
    ["com.apple.mobilephone", nil] => "10"
  }.freeze

  FIXTURE = <<~TOML
    [general]
    ipcEnabled = true

    [workspaceBar]
    enabled = false
    position = "overlappingMenuBar"
    reserveLayoutSpace = false
    revealModifier = "option"

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
    binding = "Option+Shift+Right Arrow"
    id = "move.right"

    [[hotkeys]]
    binding = "Option+Shift+Up Arrow"
    id = "move.up"

    [[hotkeys]]
    binding = "Option+Shift+Down Arrow"
    id = "move.down"

    [[hotkeys]]
    binding = "Option+Left Arrow"
    id = "focus.left"

    [[hotkeys]]
    binding = "Option+Right Arrow"
    id = "focus.right"

    [[hotkeys]]
    binding = "Option+Up Arrow"
    id = "focus.up"

    [[hotkeys]]
    binding = "Option+Down Arrow"
    id = "focus.down"

    [[hotkeys]]
    binding = "Control+Option+Shift+Up Arrow"
    id = "moveWindowToWorkspaceUp"

    [[hotkeys]]
    binding = "Control+Option+Shift+Down Arrow"
    id = "moveWindowToWorkspaceDown"

    [[hotkeys]]
    binding = "Control+Option+Shift+Left Arrow"
    id = "moveColumn.left"

    [[hotkeys]]
    binding = "Control+Option+Shift+R"
    id = "moveColumn.right"

    [[hotkeys]]
    binding = "Control+Option+Shift+Right Arrow"
    id = "custom.conflictingAction"

    [[hotkeys]]
    binding = "Control+Option+T"
    id = "toggleScratchpadWindow"

    [[hotkeys]]
    binding = "Control+Option+H"
    id = "custom.cheatsheetConflict"

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

  def run_helper(path, *arguments, rules: RULES)
    Open3.capture3(HELPER, path, "--rules", rules, *arguments)
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
      directional_bindings = {
        "focus.left" => "Control+Option+Left Arrow",
        "focus.right" => "Control+Option+Right Arrow",
        "focus.up" => "Control+Option+Up Arrow",
        "focus.down" => "Control+Option+Down Arrow",
        "move.left" => "Control+Option+Shift+Left Arrow",
        "move.right" => "Control+Option+Shift+Right Arrow",
        "move.up" => "Control+Option+Shift+Up Arrow",
        "move.down" => "Control+Option+Shift+Down Arrow"
      }
      directional_bindings.each do |identifier, binding|
        assert_includes result, %(binding = "#{binding}"\nid = "#{identifier}")
      end
      %w[
        moveWindowToWorkspaceUp
        moveWindowToWorkspaceDown
        moveColumn.left
        custom.conflictingAction
      ].each do |identifier|
        assert_includes result, %(binding = "Unassigned"\nid = "#{identifier}")
      end
      assert_includes result, "binding = \"Control+Option+Shift+R\"\nid = \"moveColumn.right\""
      refute_includes ghostty_rule, "assignToWorkspace = "
      assert_includes ghostty_rule, "minHeight = 400.0"
      assert_includes unrelated_rule, 'assignToWorkspace = "6"'
      refute_includes result, 'bundleId = "com.google.Chrome"'
      assert_includes result, "binding = \"Unassigned\"\nid = \"toggleScratchpadWindow\""
    end
  end

  def test_reserves_cheatsheet_shortcut
    with_settings do |path|
      _out, err, status = run_helper(path)
      result = File.read(path)

      assert status.success?, err
      assert_includes result,
        "binding = \"Unassigned\"\nid = \"custom.cheatsheetConflict\""
    end
  end

  def test_adds_exact_cheatsheet_floating_rule_in_both_modes
    [[], ["--activate-assignments"]].each do |arguments|
      legacy_rule = <<~TOML

        [[appRules]]
        bundleId = "org.hammerspoon.Hammerspoon"
        titleSubstring = "OmniWM Cheat Sheet"
        id = "legacy-cheatsheet-rule"
        layout = "float"
      TOML
      with_settings(FIXTURE + legacy_rule) do |path|
        2.times do
          _out, err, status = run_helper(path, *arguments)
          assert status.success?, err
        end
        result = File.read(path)
        rule = app_rule(
          result,
          "org.hammerspoon.Hammerspoon",
          title_regex: "^OmniWM Cheat Sheet$"
        )

        assert_equal 1,
          result.scan(/^bundleId = "org\.hammerspoon\.Hammerspoon"$/).length
        assert_includes rule, 'layout = "float"'
        assert_includes rule, 'titleRegex = "^OmniWM Cheat Sheet$"'
        refute_includes rule, "titleSubstring = "
        refute_includes rule, "assignToWorkspace = "
      end
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
      assert_equal 18, result.scan(/^assignToWorkspace = /).length
      assert_includes app_rule(result, "com.mitchellh.ghostty"), 'assignToWorkspace = "3"'
      assert_includes app_rule(result, "com.mitchellh.ghostty"), "minHeight = 400.0"
      EXPECTED_ASSIGNMENTS.each do |(bundle_id, title_regex), workspace|
        rule = app_rule(result, bundle_id, title_regex: title_regex)
        assert_includes rule, %(assignToWorkspace = "#{workspace}")
      end
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
      refute_includes app_rule(result, "com.google.Chrome"), "assignToWorkspace = "
    end
  end

  def test_rules_with_additional_selectors_are_preserved_in_both_modes
    custom_rules = FIXTURE + <<~TOML

      [[appRules]]
      bundleId = "com.mitchellh.ghostty"
      titleRegex = "^Special Terminal$"
      id = "custom-ghostty-rule"
      assignToWorkspace = "6"

      [[appRules]]
      bundleId = "com.apple.Photos"
      axRole = "AXDialog"
      id = "custom-photos-rule"
      assignToWorkspace = "9"
    TOML

    [[], ["--activate-assignments"]].each do |arguments|
      with_settings(custom_rules) do |path|
        _out, err, status = run_helper(path, *arguments)
        result = File.read(path)

        assert status.success?, err
        assert_includes result, <<~TOML
          bundleId = "com.mitchellh.ghostty"
          titleRegex = "^Special Terminal$"
          id = "custom-ghostty-rule"
          assignToWorkspace = "6"
        TOML
        assert_includes result, <<~TOML
          bundleId = "com.apple.Photos"
          axRole = "AXDialog"
          id = "custom-photos-rule"
          assignToWorkspace = "9"
        TOML
      end
    end
  end

  def test_active_mode_removes_superseded_narrow_browser_assignments
    legacy_rules = FIXTURE + <<~TOML

      [[appRules]]
      bundleId = "com.google.Chrome"
      titleSubstring = "ChatGPT"
      id = "legacy-chatgpt-rule"
      assignToWorkspace = "4"

      [[appRules]]
      bundleId = "com.brave.Browser"
      titleSubstring = "Parental Controls"
      id = "legacy-shopping-rule"
      layout = "float"
      assignToWorkspace = "5"
    TOML

    with_settings(legacy_rules) do |path|
      _out, err, status = run_helper(path, "--activate-assignments")
      result = File.read(path)

      assert status.success?, err
      refute_includes result, 'titleSubstring = "ChatGPT"'
      brave_legacy = app_rule(result, "com.brave.Browser", "Parental Controls")
      assert_includes brave_legacy, 'layout = "float"'
      refute_includes brave_legacy, "assignToWorkspace = "
      assert_includes app_rule(result, "com.google.Chrome"), 'assignToWorkspace = "4"'
      assert_includes app_rule(result, "com.brave.Browser"), 'assignToWorkspace = "5"'
    end
  end

  def test_invalid_manifests_are_rejected_without_changing_settings
    cases = {
      "malformed JSON" => "{",
      "top-level object" => JSON.generate({"bundleId" => "example"}),
      "unknown key" => JSON.generate([{"bundleId" => "example", "workspace" => "1", "extra" => true}]),
      "missing selector" => JSON.generate([{"workspace" => "1"}]),
      "empty selector" => JSON.generate([{"bundleId" => "", "workspace" => "1"}]),
      "invalid workspace" => JSON.generate([{"bundleId" => "example", "workspace" => "11"}]),
      "duplicate selector" => JSON.generate([
        {"bundleId" => "example", "workspace" => "1"},
        {"bundleId" => "example", "workspace" => "2"}
      ])
    }

    cases.each do |name, manifest|
      Dir.mktmpdir do |directory|
        rules = File.join(directory, "rules.json")
        File.write(rules, manifest)
        with_settings do |path|
          before = File.binread(path)
          out, err, status = run_helper(path, rules: rules)

          refute status.success?, name
          assert_empty out, name
          assert_includes err, "configure-omniwm-settings:", name
          assert_equal before, File.binread(path), name
        end
      end
    end
  end

  def test_default_manifest_path_is_used
    with_settings do |path|
      out, err, status = Open3.capture3(HELPER, path, "--activate-assignments")

      assert status.success?, err
      assert_equal "changed\n", out
      assert_includes app_rule(File.read(path), "com.apple.Safari", title_regex: "^Development —"),
        'assignToWorkspace = "3"'
    end
  end

  def test_rules_option_order_does_not_change_results
    with_settings do |path|
      first_out, first_err, first_status = Open3.capture3(
        HELPER, path, "--activate-assignments", "--rules", RULES, "--check"
      )
      second_out, second_err, second_status = Open3.capture3(
        HELPER, path, "--check", "--rules", RULES, "--activate-assignments"
      )

      assert first_status.success?, first_err
      assert second_status.success?, second_err
      assert_equal first_out, second_out
      assert_equal FIXTURE, File.read(path)
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

  def test_creates_missing_workspaces_one_through_seven_once
    missing_workspaces = FIXTURE.gsub(
      /^\[\[workspaces\]\]\nid = "workspace-[2-7]".*?(?=^\[\[workspaces\]\]|\z)/m,
      ""
    )

    with_settings(missing_workspaces) do |path|
      _out, err, status = run_helper(path)
      assert status.success?, err
      first_result = File.binread(path)

      out, err, status = run_helper(path)
      assert status.success?, err
      assert_equal "unchanged\n", out
      assert_equal first_result, File.binread(path)

      workspace_ids = []
      %w[1 2 3 4 5 6 7 8 9 10].each do |name|
        assert_equal 1, first_result.scan(/^name = "#{name}"$/).length
        block = workspace_block(first_result, name)
        assert_includes block, 'layoutType = "niri"'
        assert_includes block, "[workspaces.monitorAssignment]\ntype = \"main\""
        workspace_ids << block[/^id = "([^"]+)"$/, 1]
      end
      assert_equal workspace_ids.length, workspace_ids.uniq.length
      assert_includes first_result, 'id = "648F6110-0272-48E5-8E62-722922C13163"'
      assert_includes first_result, 'id = "E44F8587-BA63-407F-9962-80F27D57BE23"'
    end
  end

  def test_preserves_existing_workspace_id
    existing = FIXTURE + <<~TOML

      [[workspaces]]
      id = "existing-workspace-8"
      name = "8"
      layoutType = "dwindle"

      [workspaces.monitorAssignment]
      type = "secondary"
    TOML

    with_settings(existing) do |path|
      out, err, status = run_helper(path)
      result = File.read(path)
      workspace = workspace_block(result, "8")

      assert status.success?, err
      assert_equal "changed\n", out
      assert_includes workspace, 'id = "existing-workspace-8"'
      assert_includes workspace, 'layoutType = "niri"'
      assert_includes workspace, "[workspaces.monitorAssignment]\ntype = \"main\""
      refute_includes result, 'id = "4371F67B-B469-470D-89C6-D8FBB5E65BD3"'

      out, err, status = run_helper(path)
      assert status.success?, err
      assert_equal "unchanged\n", out
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

  def test_check_reports_pending_change_without_changing_source
    with_settings do |path|
      before = File.binread(path)
      out, err, status = run_helper(path, "--check")

      assert status.success?, err
      assert_equal "changed\n", out
      assert_equal before, File.binread(path)
    end
  end

  def test_check_reports_unchanged_after_reconciliation
    with_settings do |path|
      _out, err, status = run_helper(path)
      assert status.success?, err
      before = File.binread(path)

      out, err, status = run_helper(path, "--check")

      assert status.success?, err
      assert_equal "unchanged\n", out
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

  def workspace_block(document, name)
    block = document.scan(/^\[\[workspaces\]\]\n(.*?)(?=^\[\[|\z)/m).flatten.find do |candidate|
      candidate.match?(/^name = "#{Regexp.escape(name)}"$/)
    end
    refute_nil block, "missing workspace #{name}"
    block
  end

  def app_rule(document, bundle_id, title_substring = nil, title_regex: nil)
    rule = document.scan(/^\[\[appRules\]\]\n(.*?)(?=^\[\[|\z)/m).flatten.find do |candidate|
      next false unless candidate.include?(%(bundleId = "#{bundle_id}"))

      if title_regex
        candidate.include?(%(titleRegex = "#{title_regex}"))
      elsif title_substring
        candidate.include?(%(titleSubstring = "#{title_substring}"))
      else
        !candidate.match?(/^title(?:Regex|Substring) = /)
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
