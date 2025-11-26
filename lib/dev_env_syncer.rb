# frozen_string_literal: true

require 'open3'
require 'fileutils'

module DevEnvSyncer
  class SyncError < StandardError; end

  class << self
    # Sync .coding-agent from local to Codespace
    # @param source_dir [String] local directory path (must contain .coding-agent/)
    # @param codespace_name [String] name of target Codespace
    # @param remote_path [String] absolute path to workspace directory in Codespace
    # @param codespace_repository [String, nil] full repository name (owner/repo) of the Codespace
    def sync_to_codespace(source_dir, codespace_name, remote_path, codespace_repository: nil)
      # Sync .coding-agent directory
      local_coding_agent_path = File.join(source_dir, '.coding-agent')
      if Dir.exist?(local_coding_agent_path)
        puts "\n==> Syncing .coding-agent to Codespace..."
        puts "    Local: #{local_coding_agent_path}/"
        remote_coding_agent_path = remote_path # remote_path is already the full path to the directory
        puts "    Remote: #{codespace_name}:#{remote_coding_agent_path}"

        create_cmd = "gh codespace ssh -c #{codespace_name} -- 'mkdir -p #{remote_coding_agent_path}'"
        system(create_cmd)
        raise SyncError, "Failed to create remote directory: #{remote_coding_agent_path}" unless $?.success?

        workspace_dir = File.dirname(remote_coding_agent_path)
        tar_cmd = "tar -czf - -C #{source_dir} .coding-agent | gh codespace ssh -c #{codespace_name} -- 'tar -xzf - -C #{workspace_dir} --skip-old-files 2>/dev/null || true'"
        _stdout, stderr, status = Open3.capture3(tar_cmd)
        unless status.success?
          raise SyncError, "Failed to sync .coding-agent to Codespace: #{stderr}"
        end
        puts "==> .coding-agent sync to Codespace complete!"
      else
        puts "No .coding-agent directory found at #{local_coding_agent_path}, skipping sync"
      end

      # Sync .claude/settings.local.json only if repositories match
      workspace_dir = File.dirname(remote_path)
      if codespace_repository && repositories_match?(source_dir, codespace_repository)
        sync_claude_settings_to_codespace(source_dir, codespace_name, workspace_dir)
      elsif codespace_repository
        puts "Skipping .claude/settings.local.json sync (local repo doesn't match Codespace)"
      end

      true
    end

    private

    def repositories_match?(local_dir, codespace_repository)
      remote_url = `git -C #{local_dir} remote get-url origin 2>/dev/null`.strip
      return false if remote_url.empty?

      # Normalize GitHub URLs to owner/repo format
      local_repo = normalize_github_repo(remote_url)
      return false unless local_repo

      local_repo.downcase == codespace_repository.downcase
    end

    def normalize_github_repo(url)
      # Handle SSH: git@github.com:owner/repo.git
      if url =~ %r{git@github\.com:(.+?)(?:\.git)?$}
        return Regexp.last_match(1)
      end

      # Handle HTTPS: https://github.com/owner/repo.git
      if url =~ %r{https://github\.com/(.+?)(?:\.git)?$}
        return Regexp.last_match(1)
      end

      nil
    end

    def sync_claude_settings_to_codespace(source_dir, codespace_name, remote_workspace_dir)
      sync_file(
        direction: :to,
        local_dir: source_dir,
        codespace_name: codespace_name,
        remote_workspace_dir: remote_workspace_dir,
        file_path: '.claude/settings.local.json'
      )
    end

    def sync_file(direction:, local_dir:, codespace_name:, remote_workspace_dir:, file_path:)
      return unless direction == :to

      local_file = File.join(local_dir, file_path)
      remote_file = File.join(remote_workspace_dir, file_path)

      return unless File.exist?(local_file)

      puts "==> Syncing #{file_path} to Codespace..."
      remote_dir = File.dirname(remote_file)
      create_cmd = "gh codespace ssh -c #{codespace_name} -- mkdir -p '#{remote_dir}'"
      system(create_cmd)
      raise SyncError, "Failed to create remote directory: #{remote_dir}" unless $?.success?

      copy_cmd = "cat #{local_file} | gh codespace ssh -c #{codespace_name} -- \"cat > #{remote_file}\""
      stdout, stderr, status = Open3.capture3(copy_cmd)

      unless status.success?
        raise SyncError, "Failed to sync #{file_path}: #{stderr}"
      end

      true
    end
  end
end
