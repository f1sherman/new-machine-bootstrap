#!/usr/bin/env ruby
require 'minitest/autorun'
require 'json'
require 'tmpdir'
require 'open3'
require 'socket'
require 'fileutils'

class PstackModelsTest < Minitest::Test
  SCRIPT = File.expand_path('../roles/common/files/config/skills/pstack/pstack/models.rb', __dir__)
  def setup
    @root = Dir.mktmpdir('pstack-models-')
    @home = File.join(@root, 'home')
    FileUtils.mkdir_p(@home)
    @catalog = file('catalog', [{model: 'test/fast', thinking: ['medium']}, {model: 'test/deep', thinking: ['high']}])
  end
  def teardown
    FileUtils.remove_entry(@root)
  end
  def file(name, data)
    path = File.join(@root, "#{name}.json")
    File.write(path, JSON.generate(data))
    path
  end
  def cli(*args, home: @home)
    out, err, status = Open3.capture3({'HOME'=>home}, RbConfig.ruby, SCRIPT, *args)
    [JSON.parse(out), status.success?, err]
  end
  def profile(roles = {'how explainer'=>[{model: 'test/deep', thinking: 'high'}]})
    file('profile', {version: 1, budget: 'large', roles: roles})
  end
  def save(path = profile, harness: 'pi', catalog: @catalog, home: @home)
    cli('save', harness, path, catalog, home: home)
  end
  def state
    File.join(@home, '.local/state/pstack/models/pi.json')
  end
  def test_unconfigured_and_save_resolve_across_processes
    assert_equal 'unconfigured', cli('show', 'pi')[0]['status']
    result, ok = save
    assert ok, result.inspect
    result, ok = cli('resolve', 'pi', 'how explainer', @catalog)
    assert ok, result.inspect
    assert_equal [{'model'=>'test/deep', 'thinking'=>'high'}], result['selections']
    assert_equal Socket.gethostname, JSON.parse(File.read(state))['host']
    assert_equal 0o600, File.stat(state).mode & 0o777
    assert_equal 0o700, File.stat(File.dirname(state)).mode & 0o777
    assert_equal [{'model'=>'inherit-parent'}], cli('resolve', 'pi', 'how explorer', @catalog)[0]['selections']
  end
  def test_unconfigured_and_omitted_panels_keep_two_inheriting_entries
    empty = file('no-models', [])
    %w[pi claude-code].each do |harness|
      %w[arena\ runners arena\ cross-judge\ pool architect\ runners interrogate\ reviewers].each do |role|
        result, ok = cli('resolve', harness, role, empty)
        assert ok, result.inspect
        assert_equal [{'model'=>'inherit-parent'}, {'model'=>'inherit-parent'}], result['selections']
      end
    end
    assert save[1]
    assert_equal 2, cli('resolve', 'pi', 'architect runners', empty)[0]['selections'].length
  end
  def test_panel_aliases_and_harness_separation
    selections = [{model: 'test/fast'}, {model: 'inherit-parent'}, {model: 'auto'}]
    assert save(profile({'architect runners'=>selections}))[1]
    result, ok = cli('resolve', 'pi', 'architect runners', @catalog)
    assert ok
    assert_equal 3, result['selections'].length
    assert_equal 'unconfigured', cli('show', 'claude-code')[0]['status']
    other = File.join(@root, 'other-home')
    FileUtils.mkdir_p(other)
    assert_equal 'unconfigured', cli('show', 'pi', home: other)[0]['status']
  end
  def test_stale_catalog_does_not_silently_inherit
    assert save[1]
    result, ok = cli('resolve', 'pi', 'how explainer', file('empty', []))
    refute ok
    assert_equal 'model_unavailable', result['error']
    refute result.key?('selections')
  end
  def test_invalid_save_preserves_previous_profile
    assert save[1]
    before = File.binread(state)
    [{model: 'test/missing'}, {model: 'test/deep', thinking: 'max'}, {model: 'inherit-parent', thinking: 'high'}].each do |selection|
      refute save(profile({'how explainer'=>[selection]}))[1]
      assert_equal before, File.binread(state)
    end
    refute save(profile({'how explainer'=>[{model: 'test/fast'}, {model: 'test/deep'}]}))[1]
    assert_equal before, File.binread(state)
  end
  def test_claude_has_its_own_catalog_and_no_pi_thinking_fields
    claude = file('claude', [{model: 'balanced', thinking: []}])
    assert save(profile({'how explorer'=>[{model: 'balanced'}]}), harness: 'claude-code', catalog: claude)[1]
    refute save(profile, harness: 'claude-code')[1]
    assert_equal 'unconfigured', cli('show', 'pi')[0]['status']
  end
  def test_copied_host_profile_is_not_used
    assert save[1]
    data = JSON.parse(File.read(state))
    data['host'] = "not-#{Socket.gethostname}"
    File.write(state, JSON.generate(data))
    result, ok = cli('resolve', 'pi', 'how explainer', @catalog)
    refute ok
    assert_equal 'profile_identity_mismatch', result['error']
  end
  def test_symlink_cannot_redirect_profile_writes
    assert save[1]
    outside = file('outside', {untouched: true})
    File.unlink(state)
    File.symlink(outside, state)
    result, ok = save
    refute ok
    assert_equal 'unsafe_state_path', result['error']
    assert_equal({'untouched'=>true}, JSON.parse(File.read(outside)))
  end
  def test_concurrent_saves_are_complete_and_serialized
    assert save[1]
    first = file('first', {version: 1, budget: 'small', roles: {'how explorer'=>[{model: 'test/fast'}]}})
    second = file('second', {version: 1, budget: 'large', roles: {'how explainer'=>[{model: 'test/deep'}]}})
    threads = [first, second].map { |path| Thread.new { save(path) } }
    threads.each { |thread| assert thread.value[1], thread.value.inspect }
    data = JSON.parse(File.read(state))
    assert [JSON.parse(File.read(first))['roles'], JSON.parse(File.read(second))['roles']].include?(data['roles'])
    assert_empty Dir.glob(File.join(File.dirname(state), '.profile-*'))
  end
  def test_symlinked_state_directory_is_rejected
    outside = File.join(@root, 'outside-state')
    FileUtils.mkdir_p([outside, File.join(@home, '.local/state')])
    File.symlink(outside, File.join(@home, '.local/state/pstack'))
    result, ok = save
    refute ok
    assert_equal 'unsafe_state_path', result['error']
    assert_empty Dir.children(outside)
  end
  def test_invalid_json_fails_without_changing_state
    assert save[1]
    before = File.binread(state)
    invalid = File.join(@root, 'bad.json')
    File.write(invalid, '{')
    refute save(invalid)[1]
    assert_equal before, File.binread(state)
  end
end
