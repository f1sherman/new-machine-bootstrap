#!/usr/bin/env ruby
require 'json'
require 'socket'
require 'fileutils'
require 'tempfile'

# Role labels follow upstream setup-pstack. No model choices live in this file.
PANELS = ['arena runners', 'arena cross-judge pool', 'architect runners', 'interrogate reviewers'].freeze
ROLES = ['feature, refactoring', 'bug-fix', 'perf-issue', 'hillclimb', 'judgment and prose',
         'hardest tasks', 'how explorer', 'how explainer', 'why investigators', 'why synthesizer',
         'reflect tooling', 'reflect judgment, divergent, synthesizer', 'swarm workers', *PANELS].freeze
LEVELS = %w[off minimal low medium high xhigh max].freeze
ALIASES = %w[inherit-parent auto].freeze

class ProfileError < StandardError; end

def reject_profile(category)
  raise ProfileError, category
end

def read_json(path)
  reject_profile('input_too_large') if File.size(path) > 65_536
  JSON.parse(File.binread(path))
rescue JSON::ParserError, EncodingError
  reject_profile('invalid_json')
end

def validate_profile(data, harness, identity: false)
  reject_profile('invalid_profile') unless data.is_a?(Hash) && data['version'] == 1 &&
    %w[small medium large unlimited].include?(data['budget']) && data['roles'].is_a?(Hash) &&
    (data.keys - %w[version budget roles host harness]).empty?
  if identity || data.key?('host') || data.key?('harness')
    reject_profile('profile_identity_mismatch') unless data['host'] == Socket.gethostname && data['harness'] == harness
  end
  data['roles'].each do |role, selections|
    reject_profile('invalid_role') unless ROLES.include?(role)
    limit = PANELS.include?(role) ? 16 : 1
    reject_profile('invalid_selections') unless selections.is_a?(Array) && selections.length.between?(1, limit)
    selections.each do |selection|
      reject_profile('invalid_selection') unless selection.is_a?(Hash) &&
        (selection.keys - %w[model thinking]).empty? && selection['model'].is_a?(String) &&
        selection['model'].length.between?(1, 256) && !selection['model'].match?(/[\s\x00-\x1f]/)
      next unless selection.key?('thinking')
      reject_profile('unsupported_thinking') unless harness == 'pi' &&
        !ALIASES.include?(selection['model']) && LEVELS.include?(selection['thinking'])
    end
  end
  data
end

def catalog_from(path)
  entries = read_json(path)
  reject_profile('invalid_catalog') unless entries.is_a?(Array)
  catalog = {}
  entries.each do |entry|
    reject_profile('invalid_catalog') unless entry.is_a?(Hash) && entry['model'].is_a?(String) &&
      entry['thinking'].is_a?(Array) && (entry['thinking'] - LEVELS).empty? && !catalog.key?(entry['model'])
    catalog[entry['model']] = entry['thinking']
  end
  catalog
end

def validate_choices(selections, catalog)
  selections.each do |selection|
    model = selection.fetch('model')
    next if ALIASES.include?(model)
    reject_profile('model_unavailable') unless catalog.key?(model)
    if selection.key?('thinking') && !catalog.fetch(model).include?(selection['thinking'])
      reject_profile('unsupported_thinking')
    end
  end
end

def state_root(create: false)
  root = Dir.home
  %w[.local state pstack models].each do |part|
    root = File.join(root, part)
    if File.exist?(root) || File.symlink?(root)
      reject_profile('unsafe_state_path') if File.symlink?(root) || !File.directory?(root) || File.stat(root).uid != Process.uid
    elsif create
      Dir.mkdir(root, 0o700)
    end
  end
  if create
    File.chmod(0o700, File.dirname(root))
    File.chmod(0o700, root)
  end
  root
end

def check_state_file(path)
  return unless File.exist?(path) || File.symlink?(path)
  reject_profile('unsafe_state_path') if File.symlink?(path) || !File.file?(path) || File.stat(path).uid != Process.uid
end

def load_profile(harness)
  path = File.join(state_root, "#{harness}.json")
  check_state_file(path)
  return nil unless File.exist?(path)
  validate_profile(read_json(path), harness, identity: true)
end

begin
  command, harness, *args = ARGV
  if command == 'roles' && harness.nil?
    puts JSON.generate(ROLES.to_h { |role| [role, {panel: PANELS.include?(role)}] })
    exit
  end
  reject_profile('invalid_harness') unless %w[pi claude-code].include?(harness)
  result = case command
  when 'show'
    reject_profile('invalid_arguments') unless args.empty?
    profile = load_profile(harness)
    {status: profile ? 'configured' : 'unconfigured', profile: profile}
  when 'save'
    reject_profile('invalid_arguments') unless args.length == 2
    profile = validate_profile(read_json(args[0]), harness)
    catalog = catalog_from(args[1])
    profile['roles'].each_value { |selections| validate_choices(selections, catalog) }
    profile = profile.merge('host' => Socket.gethostname, 'harness' => harness)
    root = state_root(create: true)
    lock_path = File.join(root, "#{harness}.lock")
    check_state_file(lock_path)
    File.open(lock_path, File::RDWR | File::CREAT | File::NOFOLLOW, 0o600) do |lock|
      lock.flock(File::LOCK_EX)
      destination = File.join(root, "#{harness}.json")
      check_state_file(destination)
      Tempfile.create(['.profile-', '.json'], root) do |temp|
        temp.chmod(0o600)
        temp.write(JSON.pretty_generate(profile) + "\n")
        temp.flush
        temp.fsync
        File.rename(temp.path, destination)
      end
      File.open(root, File::RDONLY) { |directory| directory.fsync }
    end
    {status: 'saved', profile: profile}
  when 'resolve'
    reject_profile('invalid_arguments') unless args.length == 2 && ROLES.include?(args[0])
    profile = load_profile(harness)
    selections = profile&.fetch('roles')&.fetch(args[0], nil) || [{'model' => 'inherit-parent'}]
    validate_choices(selections, catalog_from(args[1]))
    {status: profile ? 'configured' : 'unconfigured', selections: selections}
  else
    reject_profile('invalid_command')
  end
  puts JSON.generate(result)
rescue ProfileError => error
  puts JSON.generate(error: error.message)
  exit 1
rescue SystemCallError, IOError
  puts JSON.generate(error: 'profile_io_error')
  exit 1
end
