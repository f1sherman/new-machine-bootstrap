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
    def sync_to_codespace(source_dir, codespace_name, remote_path)
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

      # Sync .claude/settings.local.json
      workspace_dir = File.dirname(remote_path)
      sync_claude_settings_to_codespace(source_dir, codespace_name, workspace_dir)

      true
    end

    # Sync .coding-agent from Codespace back to local
    # @param dest_dir [String] local directory path (will create .coding-agent/ if needed)
    # @param codespace_name [String] name of source Codespace
    # @param remote_path [String] absolute path to .coding-agent in Codespace
    def sync_from_codespace(dest_dir, codespace_name, remote_path)
      # Sync .coding-agent directory
      local_coding_agent_path = File.join(dest_dir, '.coding-agent')
      FileUtils.mkdir_p(local_coding_agent_path)
      remote_coding_agent_path = remote_path

      puts "\n==> Syncing .coding-agent from Codespace..."
      puts "    Remote: #{codespace_name}:#{remote_coding_agent_path}"
      puts "    Local: #{local_coding_agent_path}/"

      check_cmd = "gh codespace ssh -c #{codespace_name} -- 'test -d #{remote_coding_agent_path}'"
      if system(check_cmd)
        workspace_dir = File.dirname(remote_coding_agent_path)
        tar_cmd = "gh codespace ssh -c #{codespace_name} -- 'tar -czf - -C #{workspace_dir} .coding-agent' | tar -xzf - -C #{dest_dir} --skip-old-files 2>/dev/null || true"
        _stdout, stderr, status = Open3.capture3(tar_cmd)
        unless status.success?
          raise SyncError, "Failed to sync .coding-agent from Codespace: #{stderr}"
        end
        puts "==> .coding-agent sync from Codespace complete!"
      else
        puts "No .coding-agent directory found in Codespace, skipping sync"
      end

      # Sync .claude/settings.local.json
      workspace_dir = File.dirname(remote_path)
      sync_claude_settings_from_codespace(dest_dir, codespace_name, workspace_dir)

      true
    end

    private

    def sync_claude_settings_to_codespace(source_dir, codespace_name, remote_workspace_dir)
      sync_file(
        direction: :to,
        local_dir: source_dir,
        codespace_name: codespace_name,
        remote_workspace_dir: remote_workspace_dir,
        file_path: '.claude/settings.local.json'
      )
    end

    def sync_claude_settings_from_codespace(dest_dir, codespace_name, remote_workspace_dir)
      sync_file(
        direction: :from,
        local_dir: dest_dir,
        codespace_name: codespace_name,
        remote_workspace_dir: remote_workspace_dir,
        file_path: '.claude/settings.local.json'
      )
    end

    def sync_file(direction:, local_dir:, codespace_name:, remote_workspace_dir:, file_path:)
      local_file = File.join(local_dir, file_path)
      remote_file = File.join(remote_workspace_dir, file_path)

      case direction
      when :to
        return unless File.exist?(local_file)
        puts "==> Syncing #{file_path} to Codespace..."
        remote_dir = File.dirname(remote_file)
        create_cmd = "gh codespace ssh -c #{codespace_name} -- mkdir -p '#{remote_dir}'"
        system(create_cmd)
        raise SyncError, "Failed to create remote directory: #{remote_dir}" unless $?.success?

        copy_cmd = "cat #{local_file} | gh codespace ssh -c #{codespace_name} -- \"cat > #{remote_file}\""
      when :from
        # Check if remote file exists
        check_cmd = "gh codespace ssh -c #{codespace_name} -- test -f #{remote_file}"
        return unless system(check_cmd)
        puts "==> Syncing #{file_path} from Codespace..."
        FileUtils.mkdir_p(File.dirname(local_file))
        copy_cmd = "gh codespace ssh -c #{codespace_name} -- cat #{remote_file} > #{local_file}"
      else
        raise ArgumentError, "Invalid sync direction: #{direction}"
      end

      stdout, stderr, status = Open3.capture3(copy_cmd)

      unless status.success?
        raise SyncError, "Failed to sync #{file_path}: #{stderr}"
      end

      true
    end
  end
end
