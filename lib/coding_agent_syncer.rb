# frozen_string_literal: true

require 'open3'
require 'fileutils'

module CodingAgentSyncer
  class SyncError < StandardError; end

  class << self
    # Sync .coding-agent from local to Codespace
    # @param source_dir [String] local directory path (must contain .coding-agent/)
    # @param codespace_name [String] name of target Codespace
    # @param remote_path [String] absolute path to workspace directory in Codespace
    def sync_to_codespace(source_dir, codespace_name, remote_path)
      local_path = File.join(source_dir, '.coding-agent/')

      unless Dir.exist?(local_path)
        puts "No .coding-agent directory found at #{local_path}, skipping sync"
        return true
      end

      remote_target = "#{remote_path}/"

      puts "\n==> Syncing .coding-agent to Codespace..."
      puts "    Local: #{local_path}"
      puts "    Remote: #{codespace_name}:#{remote_target}"

      create_cmd = "gh codespace ssh -c #{codespace_name} -- 'mkdir -p #{remote_path}'"
      system(create_cmd)

      unless $?.success?
        raise SyncError, "Failed to create remote directory: #{remote_path}"
      end

      rsync_cmd = [
        'rsync',
        '--archive',          # preserve permissions, timestamps, symlinks, etc.
        '--compress',         # compress data during transfer
        '--ignore-existing',  # skip files that exist on receiver (append-only)
        '-e', "gh codespace ssh -c #{codespace_name} --",
        local_path,
        "remote:#{remote_target}"
      ].join(' ')

      stdout, stderr, status = Open3.capture3(rsync_cmd)

      unless status.success?
        $stderr.puts "Error: Failed to sync to Codespace"
        $stderr.puts stderr unless stderr.empty?
        raise SyncError, "Rsync failed with exit code #{status.exitstatus}"
      end

      puts "==> Sync to Codespace complete!"
      true
    end

    # Sync .coding-agent from Codespace back to local
    # @param dest_dir [String] local directory path (will create .coding-agent/ if needed)
    # @param codespace_name [String] name of source Codespace
    # @param remote_path [String] absolute path to .coding-agent in Codespace
    def sync_from_codespace(dest_dir, codespace_name, remote_path)
      local_path = File.join(dest_dir, '.coding-agent/')
      FileUtils.mkdir_p(local_path)

      puts "\n==> Syncing .coding-agent from Codespace..."
      puts "    Remote: #{codespace_name}:#{remote_path}/"
      puts "    Local: #{local_path}"

      check_cmd = "gh codespace ssh -c #{codespace_name} -- 'test -d #{remote_path}'"
      system(check_cmd)

      unless $?.success?
        puts "No .coding-agent directory found in Codespace, skipping sync"
        return true
      end

      rsync_cmd = [
        'rsync',
        '--archive',          # preserve permissions, timestamps, symlinks, etc.
        '--compress',         # compress data during transfer
        '--ignore-existing',  # skip files that exist on receiver (append-only)
        '-e', "gh codespace ssh -c #{codespace_name} --",
        "remote:#{remote_path}/",
        local_path
      ].join(' ')

      stdout, stderr, status = Open3.capture3(rsync_cmd)

      unless status.success?
        $stderr.puts "Error: Failed to sync from Codespace"
        $stderr.puts stderr unless stderr.empty?
        raise SyncError, "Rsync failed with exit code #{status.exitstatus}"
      end

      puts "==> Sync from Codespace complete!"
      true
    end
  end
end
