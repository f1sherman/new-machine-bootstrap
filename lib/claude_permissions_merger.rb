# frozen_string_literal: true

require 'json'
require 'fileutils'

module ClaudePermissionsMerger
  SETTINGS_SUBPATH = File.join('.claude', 'settings.local.json')

  class << self
    # Find permissions in source that don't exist in destination
    # @param source_permissions [Array<String>] permissions from source
    # @param destination_settings_path [String] path to destination settings.local.json
    # @return [Array<String>] new permissions not in destination
    def find_new_permissions(source_permissions, destination_settings_path)
      destination_permissions = read_allow_permissions(destination_settings_path)
      source_permissions - destination_permissions
    end

    # Prompt user for each new permission and merge accepted ones into destination
    # @param new_permissions [Array<String>] permissions to prompt about
    # @param destination_settings_path [String] path to destination settings.local.json
    def prompt_and_merge(new_permissions, destination_settings_path)
      return if new_permissions.empty?

      puts "\n==> Found #{new_permissions.length} new permission(s)"

      permissions_to_add = []

      new_permissions.each do |permission|
        print "    Add '#{permission}'? [y/N] "
        $stdout.flush
        response = $stdin.gets&.strip&.downcase
        permissions_to_add << permission if response == 'y'
      end

      return if permissions_to_add.empty?

      settings = if File.exist?(destination_settings_path)
                   JSON.parse(File.read(destination_settings_path))
                 else
                   { 'permissions' => { 'allow' => [], 'deny' => [] } }
                 end

      settings['permissions'] ||= {}
      settings['permissions']['allow'] ||= []
      settings['permissions']['allow'].concat(permissions_to_add)

      FileUtils.mkdir_p(File.dirname(destination_settings_path))
      File.write(destination_settings_path, JSON.pretty_generate(settings) + "\n")
      puts "==> Added #{permissions_to_add.length} permission(s)"
    rescue StandardError => e
      $stderr.puts "Warning: Could not merge permissions: #{e.message}"
    end

    private

    def read_allow_permissions(settings_path)
      return [] unless File.exist?(settings_path)

      settings = JSON.parse(File.read(settings_path))
      settings.dig('permissions', 'allow') || []
    rescue JSON::ParserError
      []
    end
  end
end
