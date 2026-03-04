# frozen_string_literal: true

require 'json'
require 'open3'
require 'fileutils'
require_relative 'claude_permissions_merger'
require_relative 'remote_transport'

module DevEnvSyncer
  class SyncError < StandardError; end

  class << self
    # Sync .coding-agent from local to remote workspace
    # @param source_dir [String] local directory path (must contain .coding-agent/)
    # @param codespace_name [String] name of target workspace (used to build transport if none given)
    # @param remote_path [String] absolute path to .coding-agent directory in remote workspace
    # @param codespace_repository [String, nil] full repository name (owner/repo)
    # @param transport [RemoteTransport::CodespaceTransport, RemoteTransport::DevpodTransport, nil]
    def sync_to_codespace(source_dir, codespace_name, remote_path, codespace_repository: nil, transport: nil)
      transport ||= RemoteTransport::CodespaceTransport.new(codespace_name)
      label = transport.workspace_type

      local_coding_agent_path = File.join(source_dir, '.coding-agent')
      if Dir.exist?(local_coding_agent_path)
        puts "\n==> Syncing .coding-agent to #{label}..."
        puts "    Local: #{local_coding_agent_path}/"
        remote_coding_agent_path = remote_path
        puts "    Remote: #{transport.name}:#{remote_coding_agent_path}"

        create_cmd = "#{transport.ssh_prefix} 'mkdir -p #{remote_coding_agent_path}'"
        system(create_cmd)
        raise SyncError, "Failed to create remote directory: #{remote_coding_agent_path}" unless $?.success?

        workspace_dir = File.dirname(remote_coding_agent_path)
        tar_cmd = "COPYFILE_DISABLE=1 tar -czf - -C #{source_dir} .coding-agent | #{transport.ssh_prefix} 'tar -xzf - -C #{workspace_dir} --skip-old-files 2>/dev/null || true'"
        _stdout, stderr, status = Open3.capture3(tar_cmd)
        unless status.success?
          raise SyncError, "Failed to sync .coding-agent to #{label}: #{stderr}"
        end
        puts "==> .coding-agent sync to #{label} complete!"
      else
        puts "No .coding-agent directory found at #{local_coding_agent_path}, skipping sync"
      end

      workspace_dir = File.dirname(remote_path)
      if codespace_repository && repositories_match?(source_dir, codespace_repository)
        sync_settings_to_remote(source_dir, workspace_dir, transport: transport)
      elsif codespace_repository
        puts "Skipping .claude/settings.local.json sync (local repo doesn't match #{label})"
      end

      true
    end

    # Read a file from the remote workspace
    # @param codespace_name [String] name of source workspace
    # @param remote_file_path [String] absolute path to file in remote workspace
    # @param transport [RemoteTransport::CodespaceTransport, RemoteTransport::DevpodTransport, nil]
    # @return [String, nil] file contents or nil if file doesn't exist
    def read_remote_file(codespace_name, remote_file_path, transport: nil)
      transport ||= RemoteTransport::CodespaceTransport.new(codespace_name)

      stdout, _stderr, status = Open3.capture3(
        "#{transport.ssh_prefix} 'cat #{remote_file_path} 2>/dev/null'"
      )
      return nil unless status.success? && !stdout.empty?

      stdout
    end

    # Get new permissions from remote workspace that don't exist locally
    # @param local_dir [String] local directory path
    # @param codespace_name [String] name of source workspace
    # @param remote_workspace_dir [String] absolute path to workspace directory
    # @param transport [RemoteTransport::CodespaceTransport, RemoteTransport::DevpodTransport, nil]
    # @return [Array<String>] new permissions found in remote workspace
    def get_new_permissions_from_codespace(local_dir, codespace_name, remote_workspace_dir, transport: nil)
      remote_settings_path = File.join(remote_workspace_dir, '.claude', 'settings.local.json')
      local_settings_path = File.join(local_dir, '.claude', 'settings.local.json')

      remote_content = read_remote_file(codespace_name, remote_settings_path, transport: transport)
      return [] unless remote_content

      begin
        remote_settings = JSON.parse(remote_content)
        remote_permissions = remote_settings.dig('permissions', 'allow') || []

        ClaudePermissionsMerger.find_new_permissions(
          remote_permissions, local_settings_path, destination_dir: local_dir
        )
      rescue JSON::ParserError
        []
      end
    end

    # Sync .coding-agent from remote workspace back to local (without overwriting existing files)
    # @param local_dir [String] local directory path to sync to
    # @param codespace_name [String] name of source workspace
    # @param remote_workspace_dir [String] absolute path to workspace directory
    # @param transport [RemoteTransport::CodespaceTransport, RemoteTransport::DevpodTransport, nil]
    def sync_from_codespace(local_dir, codespace_name, remote_workspace_dir, transport: nil)
      transport ||= RemoteTransport::CodespaceTransport.new(codespace_name)
      label = transport.workspace_type
      remote_coding_agent_path = File.join(remote_workspace_dir, '.coding-agent')

      check_cmd = "#{transport.ssh_prefix} 'test -d #{remote_coding_agent_path} && echo exists'"
      stdout, _stderr, _status = Open3.capture3(check_cmd)

      unless stdout.strip == 'exists'
        puts "No .coding-agent directory in #{label}, skipping sync"
        return false
      end

      puts "\n==> Syncing .coding-agent from #{label}..."
      puts "    Remote: #{transport.name}:#{remote_coding_agent_path}"
      puts "    Local: #{File.join(local_dir, '.coding-agent')}/"

      tar_cmd = "#{transport.ssh_prefix} 'tar -czf - -C #{remote_workspace_dir} .coding-agent' | tar -xzf - -C #{local_dir} --skip-old-files 2>/dev/null || true"
      _stdout, stderr, status = Open3.capture3(tar_cmd)

      unless status.success?
        raise SyncError, "Failed to sync .coding-agent from #{label}: #{stderr}"
      end

      puts "==> .coding-agent sync from #{label} complete!"
      true
    end

    private

    def repositories_match?(local_dir, codespace_repository)
      remote_url = `git -C #{local_dir} remote get-url origin 2>/dev/null`.strip
      return false if remote_url.empty?

      local_repo = normalize_github_repo(remote_url)
      return false unless local_repo

      local_repo.downcase == codespace_repository.downcase
    end

    def normalize_github_repo(url)
      if url =~ %r{git@github\.com:(.+?)(?:\.git)?$}
        return Regexp.last_match(1)
      end

      if url =~ %r{https://github\.com/(.+?)(?:\.git)?$}
        return Regexp.last_match(1)
      end

      nil
    end

    def sync_settings_to_remote(source_dir, remote_workspace_dir, transport:)
      file_path = '.claude/settings.local.json'
      local_file = File.join(source_dir, file_path)
      remote_file = File.join(remote_workspace_dir, file_path)

      return unless File.exist?(local_file)

      puts "==> Syncing #{file_path} to #{transport.workspace_type}..."
      remote_dir = File.dirname(remote_file)
      create_cmd = "#{transport.ssh_prefix} mkdir -p '#{remote_dir}'"
      system(create_cmd)
      raise SyncError, "Failed to create remote directory: #{remote_dir}" unless $?.success?

      copy_cmd = "cat #{local_file} | #{transport.ssh_prefix} \"cat > #{remote_file}\""
      _stdout, stderr, status = Open3.capture3(copy_cmd)

      unless status.success?
        raise SyncError, "Failed to sync #{file_path}: #{stderr}"
      end

      puts "==> #{file_path} sync complete!"
      true
    end
  end
end
