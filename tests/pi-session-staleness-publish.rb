#!/usr/bin/env ruby

require "fileutils"
require "json"
require "open3"
require "tmpdir"

COMMAND = File.expand_path("../roles/common/files/bin/pi-session-staleness-publish", __dir__)
CASES = [
  :stable_directory_order,
  :manifest_relative_path_change,
  :file_content_change,
  :symlink_target_change,
  :executable_bit_change,
  :executable_mode_bits_ignore_ownership,
  :missing_path_change,
  :value_change,
  :no_op_preserves_bytes_and_mtime,
  :no_op_secures_record_mode,
  :classification_updates_are_independent,
  :invalid_present_classification,
  :invalid_prior_reason,
  :invalid_prior_changed_at,
  :producer_records_are_independent,
  :existing_state_directory_is_secured,
  :invalid_operation,
  :invalid_identifier,
  :invalid_classification,
  :invalid_reason,
  :invalid_manifest_schema,
  :duplicate_input_name,
  :relative_root,
  :escaping_relative_path,
  :prior_record_survives_hash_failure,
  :fifo_is_rejected_without_changing_prior_record,
  :durable_recovery_creation_failure_preserves_prior_record,
  :post_rename_failure_restores_prior_record,
  :post_rename_failure_removes_first_record,
  :rollback_rename_failure_retains_artifact,
  :rollback_sync_failure_retains_artifact,
  :next_run_recovers_after_failed_restoration,
  :first_write_cleanup_failure_is_reported,
  :rollback_artifact_unlink_failure_is_nonfatal,
  :stale_rollback_artifact_is_reconciled,
  :same_producer_observations_hash_under_lock,
  :readers_never_observe_partial_json,
].freeze

class PublisherTest
  def initialize
    @failures = []
  end

  def run
    CASES.each do |name|
      Dir.mktmpdir("publisher-test") do |directory|
        @root = directory
        @home = File.join(directory, "home")
        @state = File.join(directory, "state")
        FileUtils.mkdir_p(@home)
        send(name)
        puts "PASS #{name}"
      rescue StandardError => error
        @failures << "#{name}: #{error.message}"
        warn "FAIL #{name}: #{error.message}"
      end
    end

    abort @failures.join("\n") unless @failures.empty?

    puts "Pi session staleness publisher behavior passed"
  end

  private

  def assert(value, message)
    raise message unless value
  end

  def assert_equal(expected, actual, message = nil)
    raise(message || "expected #{expected.inspect}, got #{actual.inspect}") unless expected == actual
  end

  def manifest(inputs, schema: 1, extra: {})
    path = File.join(@root, "manifest-#{rand(1_000_000)}.json")
    File.write(path, JSON.generate({"schema" => schema, "inputs" => inputs}.merge(extra)))
    path
  end

  def path_input(name, root, path)
    {"type" => "path", "name" => name, "root" => root, "path" => path}
  end

  def value_input(name, value)
    {"type" => "value", "name" => name, "value" => value}
  end

  def reconcile(manifest_path, producer: "test-producer", classification: "reload", reason: "resources changed", operation: "reconcile", environment: {})
    Open3.capture3(
      {"HOME" => @home, "XDG_STATE_HOME" => @state}.merge(environment),
      COMMAND,
      operation,
      "--producer", producer,
      "--classification", classification,
      "--reason", reason,
      "--manifest", manifest_path,
    )
  end

  def reconcile!(manifest_path, **options)
    stdout, stderr, status = reconcile(manifest_path, **options)
    assert(status.success?, "command failed: #{stderr}#{stdout}")
  end

  def record_path(producer = "test-producer")
    File.join(@state, "pi-session-staleness", "v1", "producers", "#{producer}.json")
  end

  def record(producer = "test-producer")
    JSON.parse(File.read(record_path(producer)))
  end

  def producer_directory
    File.dirname(record_path)
  end

  def fault_environment(
    directory_sync_failures: 0,
    directory_sync_failure_calls: [],
    rollback_rename: false,
    rollback_unlink: false,
    destination_rename_marker: nil
  )
    wrapper = File.join(@root, "publisher-faults.rb")
    File.write(wrapper, <<~RUBY)
      class << File
        alias_method :publisher_original_open, :open
        alias_method :publisher_original_rename, :rename
        alias_method :publisher_original_unlink, :unlink

        def open(path, *arguments, **options, &block)
          if path == ENV["PUBLISHER_DIRECTORY"]
            call = ENV.fetch("PUBLISHER_DIRECTORY_SYNC_CALL", "0").to_i + 1
            ENV["PUBLISHER_DIRECTORY_SYNC_CALL"] = call.to_s
            failures = ENV.fetch("PUBLISHER_DIRECTORY_SYNC_FAILURE_CALLS", "")
              .split(",").reject(&:empty?).map(&:to_i)
            raise IOError, "injected directory sync failure" if failures.include?(call)
          end
          publisher_original_open(path, *arguments, **options, &block)
        end

        def rename(source, destination)
          marker = ENV["PUBLISHER_DESTINATION_RENAME_MARKER"]
          if marker && destination == ENV["PUBLISHER_RECORD_PATH"]
            publisher_original_open(marker, "ab") { |file| file.puts(source) }
          end
          if ENV["PUBLISHER_FAIL_ROLLBACK_RENAME"] == "1" &&
              (source.end_with?(".restore") || source.include?(".rollback"))
            raise IOError, "injected rollback rename failure"
          end
          publisher_original_rename(source, destination)
        end

        def unlink(path)
          cleanup_artifact = path.end_with?(".cleanup-only") || path.end_with?(".rollback")
          if ENV["PUBLISHER_FAIL_ROLLBACK_UNLINK"] == "1" && cleanup_artifact
            raise IOError, "injected rollback unlink failure"
          end
          publisher_original_unlink(path)
        end
      end
    RUBY
    failure_calls = directory_sync_failure_calls
    if failure_calls.empty? && directory_sync_failures.positive?
      failure_calls = (1..directory_sync_failures).to_a
    end
    {
      "PUBLISHER_DIRECTORY" => producer_directory,
      "PUBLISHER_DIRECTORY_SYNC_CALL" => "0",
      "PUBLISHER_DIRECTORY_SYNC_FAILURE_CALLS" => failure_calls.join(","),
      "PUBLISHER_FAIL_ROLLBACK_RENAME" => rollback_rename ? "1" : "0",
      "PUBLISHER_FAIL_ROLLBACK_UNLINK" => rollback_unlink ? "1" : "0",
      "PUBLISHER_DESTINATION_RENAME_MARKER" => destination_rename_marker,
      "PUBLISHER_RECORD_PATH" => record_path,
      "RUBYOPT" => "-r#{wrapper}",
    }.compact
  end

  def recovery_artifacts
    Dir.glob(File.join(producer_directory, ".test-producer.json.*.recovery-required"))
  end

  def cleanup_artifacts
    Dir.glob(File.join(producer_directory, ".test-producer.json.*.cleanup-only"))
  end

  def rollback_artifacts
    recovery_artifacts + cleanup_artifacts +
      Dir.glob(File.join(producer_directory, ".test-producer.json.*.rollback"))
  end

  def generation(classification = "reload", producer = "test-producer")
    record(producer).fetch(classification).fetch("generation")
  end

  def assert_rejected(manifest_path, **options)
    _stdout, stderr, status = reconcile(manifest_path, **options)
    assert(!status.success?, "invalid command succeeded")
    assert(stderr.start_with?("pi-session-staleness-publish: "), "error lacks prefix: #{stderr.inspect}")
  end

  def stable_directory_order
    directory = File.join(@root, "tree")
    FileUtils.mkdir_p(directory)
    File.write(File.join(directory, "b"), "second")
    File.write(File.join(directory, "a"), "first")
    input = manifest([path_input("tree", @root, "tree")])
    reconcile!(input)
    first = generation
    FileUtils.rm_rf(directory)
    FileUtils.mkdir_p(directory)
    File.write(File.join(directory, "a"), "first")
    File.write(File.join(directory, "b"), "second")
    reconcile!(input)
    assert_equal(first, generation)
  end

  def manifest_relative_path_change
    first_path = File.join(@root, "first")
    second_path = File.join(@root, "second")
    File.write(first_path, "same content")
    File.link(first_path, second_path)
    reconcile!(manifest([path_input("file", @root, "first")]))
    first = generation
    reconcile!(manifest([path_input("file", @root, "second")]))
    assert(first != generation, "manifest-relative path did not change generation")
  end

  def file_content_change
    file = File.join(@root, "file")
    File.write(file, "before")
    input = manifest([path_input("file", @root, "file")])
    reconcile!(input)
    first = generation
    File.write(file, "after")
    reconcile!(input)
    assert(first != generation, "file content did not change generation")
  end

  def symlink_target_change
    File.symlink("first", File.join(@root, "link"))
    input = manifest([path_input("link", @root, "link")])
    reconcile!(input)
    first = generation
    File.unlink(File.join(@root, "link"))
    File.symlink("second", File.join(@root, "link"))
    reconcile!(input)
    assert(first != generation, "symlink target did not change generation")
  end

  def executable_bit_change
    file = File.join(@root, "script")
    File.write(file, "echo ok\n")
    File.chmod(0o600, file)
    input = manifest([path_input("script", @root, "script")])
    reconcile!(input)
    first = generation
    File.chmod(0o700, file)
    reconcile!(input)
    assert(first != generation, "executable bit did not change generation")
  end

  def executable_mode_bits_ignore_ownership
    file = File.join(@root, "script")
    File.write(file, "echo ok\n")
    File.chmod(0o600, file)
    input = manifest([path_input("script", @root, "script")])
    reconcile!(input)
    first = generation
    File.chmod(0o601, file)
    reconcile!(input)
    assert(first != generation, "non-owner executable bit did not change generation")
  end

  def missing_path_change
    input = manifest([path_input("optional", @root, "optional")])
    reconcile!(input)
    first = generation
    File.write(File.join(@root, "optional"), "present")
    reconcile!(input)
    assert(first != generation, "missing path transition did not change generation")
  end

  def value_change
    reconcile!(manifest([value_input("version", "one")]))
    first = generation
    reconcile!(manifest([value_input("version", "two")]))
    assert(first != generation, "value did not change generation")
  end

  def no_op_preserves_bytes_and_mtime
    input = manifest([value_input("version", "same")])
    reconcile!(input)
    state_directories = [
      File.join(@state, "pi-session-staleness"),
      File.join(@state, "pi-session-staleness", "v1"),
      File.dirname(record_path),
    ]
    state_directories.each do |directory|
      assert_equal(0o700, File.stat(directory).mode & 0o777)
    end
    bytes = File.binread(record_path)
    mtime = File.stat(record_path).mtime
    sleep 0.02
    reconcile!(input)
    assert_equal(bytes, File.binread(record_path))
    assert_equal(mtime, File.stat(record_path).mtime)
  end

  def no_op_secures_record_mode
    input = manifest([value_input("version", "same")])
    reconcile!(input)
    bytes = File.binread(record_path)
    mtime = File.stat(record_path).mtime
    File.chmod(0o666, record_path)
    reconcile!(input)
    assert_equal(0o600, File.stat(record_path).mode & 0o777)
    assert_equal(bytes, File.binread(record_path))
    assert_equal(mtime, File.stat(record_path).mtime)
  end

  def classification_updates_are_independent
    reconcile!(manifest([value_input("reload", "one")]), classification: "reload")
    reload_state = record.fetch("reload")
    reconcile!(manifest([value_input("restart", "one")]), classification: "restart")
    assert_equal(reload_state, record.fetch("reload"))
    assert(record.key?("restart"), "restart state was not added")
  end

  def invalid_present_classification
    input = manifest([value_input("version", "one")])
    reconcile!(input)
    [nil, false].each do |invalid_entry|
      invalid_record = record.merge("restart" => invalid_entry)
      File.write(record_path, JSON.generate(invalid_record) << "\n")
      bytes = File.binread(record_path)
      assert_rejected(input, classification: "restart")
      assert_equal(bytes, File.binread(record_path))
    end
  end

  def invalid_prior_reason
    input = manifest([value_input("version", "one")])
    reconcile!(input)
    invalid_record = record
    invalid_record.fetch("reload")["reason"] = "x" * 201
    File.write(record_path, JSON.generate(invalid_record) << "\n")
    bytes = File.binread(record_path)
    assert_rejected(input)
    assert_equal(bytes, File.binread(record_path))
  end

  def invalid_prior_changed_at
    input = manifest([value_input("version", "one")])
    reconcile!(input)
    ["yesterday", "2025-01-02T03:04:05Z", "2025-01-02T03:04:05.678+00:00"].each do |changed_at|
      invalid_record = record
      invalid_record.fetch("reload")["changedAt"] = changed_at
      File.write(record_path, JSON.generate(invalid_record) << "\n")
      bytes = File.binread(record_path)
      assert_rejected(input)
      assert_equal(bytes, File.binread(record_path))
    end
  end

  def producer_records_are_independent
    input = manifest([value_input("version", "one")])
    reconcile!(input, producer: "producer-one")
    first_bytes = File.binread(record_path("producer-one"))
    reconcile!(input, producer: "producer-two")
    assert_equal(first_bytes, File.binread(record_path("producer-one")))
    assert(File.file?(record_path("producer-two")), "second producer record missing")
  end

  def existing_state_directory_is_secured
    application_directory = File.join(@state, "pi-session-staleness")
    FileUtils.mkdir_p(application_directory)
    File.chmod(0o777, application_directory)
    reconcile!(manifest([]))
    assert_equal(0o700, File.stat(application_directory).mode & 0o777)
  end

  def invalid_operation
    assert_rejected(manifest([]), operation: "remove")
  end

  def invalid_identifier
    assert_rejected(manifest([]), producer: "Invalid_ID")
  end

  def invalid_classification
    assert_rejected(manifest([]), classification: "refresh")
  end

  def invalid_reason
    assert_rejected(manifest([]), reason: "x" * 201)
    assert_rejected(manifest([]), reason: "")
  end

  def invalid_manifest_schema
    assert_rejected(manifest([], schema: 2))
    assert_rejected(manifest([], extra: {"unknown" => true}))
    bad = manifest([{"type" => "value", "name" => "x", "value" => "y", "extra" => true}])
    assert_rejected(bad)
  end

  def duplicate_input_name
    input = manifest([value_input("same", "one"), value_input("same", "two")])
    assert_rejected(input)
  end

  def relative_root
    assert_rejected(manifest([path_input("file", "relative", "file")]))
  end

  def escaping_relative_path
    assert_rejected(manifest([path_input("file", @root, "../file")]))
    assert_rejected(manifest([path_input("file", @root, "./file")]))
  end

  def prior_record_survives_hash_failure
    reconcile!(manifest([value_input("version", "valid")]))
    bytes = File.binread(record_path)
    bad = manifest([path_input("child", File.join(@root, "not-directory"), "child")])
    File.write(File.join(@root, "not-directory"), "file")
    assert_rejected(bad)
    assert_equal(bytes, File.binread(record_path))
    JSON.parse(File.read(record_path))
  end

  def fifo_is_rejected_without_changing_prior_record
    reconcile!(manifest([value_input("version", "before")]))
    bytes = File.binread(record_path)
    fifo = File.join(@root, "unsupported-fifo")
    system("mkfifo", fifo) or raise "could not create FIFO"
    assert_rejected(manifest([path_input("fifo", @root, "unsupported-fifo")]))
    assert_equal(bytes, File.binread(record_path))
  end

  def durable_recovery_creation_failure_preserves_prior_record
    reconcile!(manifest([value_input("version", "before")]))
    bytes = File.binread(record_path)
    marker = File.join(@root, "destination-renames")
    changed = manifest([value_input("version", "after")])
    assert_rejected(
      changed,
      environment: fault_environment(
        directory_sync_failure_calls: [1],
        destination_rename_marker: marker,
      ),
    )
    assert_equal(bytes, File.binread(record_path))
    assert(!File.exist?(marker), "destination replacement started before recovery was durable")
    assert_equal([], rollback_artifacts)
  end

  def post_rename_failure_restores_prior_record
    reconcile!(manifest([value_input("version", "before")]))
    bytes = File.binread(record_path)
    changed = manifest([value_input("version", "after")])
    assert_rejected(
      changed,
      environment: fault_environment(directory_sync_failure_calls: [2]),
    )
    assert_equal(bytes, File.binread(record_path))
    assert_equal([], Dir.glob(File.join(producer_directory, ".test-producer.json.*")))
  end

  def post_rename_failure_removes_first_record
    input = manifest([value_input("version", "first")])
    assert_rejected(input, environment: fault_environment(directory_sync_failures: 1))
    assert(!File.exist?(record_path), "failed first write left a producer record")
    assert_equal([], Dir.glob(File.join(producer_directory, ".test-producer.json.*")))
  end

  def rollback_rename_failure_retains_artifact
    reconcile!(manifest([value_input("version", "before")]))
    bytes = File.binread(record_path)
    changed = manifest([value_input("version", "after")])
    _stdout, stderr, status = reconcile(
      changed,
      environment: fault_environment(
        directory_sync_failure_calls: [2],
        rollback_rename: true,
      ),
    )
    assert(!status.success?, "rollback rename failure succeeded")
    assert(stderr.include?("injected rollback rename failure"), "rollback failure not reported: #{stderr}")
    assert_equal(1, recovery_artifacts.length)
    assert_equal(bytes, File.binread(recovery_artifacts.first))
  end

  def rollback_sync_failure_retains_artifact
    reconcile!(manifest([value_input("version", "before")]))
    bytes = File.binread(record_path)
    changed = manifest([value_input("version", "after")])
    _stdout, stderr, status = reconcile(
      changed,
      environment: fault_environment(directory_sync_failure_calls: [2, 3]),
    )
    assert(!status.success?, "rollback sync failure succeeded")
    assert(stderr.include?("rollback failed"), "rollback sync failure not reported: #{stderr}")
    assert_equal(bytes, File.binread(record_path))
    assert_equal(1, recovery_artifacts.length)
    assert_equal(bytes, File.binread(recovery_artifacts.first))
  end

  def next_run_recovers_after_failed_restoration
    before = manifest([value_input("version", "before")])
    reconcile!(before)
    bytes = File.binread(record_path)
    changed = manifest([value_input("version", "after")])
    _stdout, _stderr, status = reconcile(
      changed,
      environment: fault_environment(
        directory_sync_failure_calls: [2],
        rollback_rename: true,
      ),
    )
    assert(!status.success?, "failed restoration unexpectedly succeeded")
    assert_equal(1, recovery_artifacts.length)

    reconcile!(before)
    assert_equal(bytes, File.binread(record_path))
    assert_equal([], recovery_artifacts)
  end

  def first_write_cleanup_failure_is_reported
    input = manifest([value_input("version", "first")])
    _stdout, stderr, status = reconcile(
      input,
      environment: fault_environment(directory_sync_failures: 2),
    )
    assert(!status.success?, "first-write cleanup failure succeeded")
    assert(stderr.include?("first-write rollback failed"), "cleanup failure not reported: #{stderr}")
    assert(!File.exist?(record_path), "failed first write left a producer record")
  end

  def rollback_artifact_unlink_failure_is_nonfatal
    reconcile!(manifest([value_input("version", "before")]))
    prior_generation = generation
    changed = manifest([value_input("version", "after")])
    _stdout, stderr, status = reconcile(
      changed,
      environment: fault_environment(rollback_unlink: true),
    )
    assert(status.success?, "durable commit failed because rollback cleanup failed: #{stderr}")
    assert(
      stderr.start_with?("pi-session-staleness-publish: warning: "),
      "cleanup warning lacks prefix: #{stderr.inspect}",
    )
    assert(stderr.include?("injected rollback unlink failure"), "cleanup failure not reported: #{stderr}")
    assert(prior_generation != generation, "durable commit did not update the record")
    assert_equal(1, rollback_artifacts.length)
  end

  def stale_rollback_artifact_is_reconciled
    reconcile!(manifest([value_input("version", "before")]))
    changed = manifest([value_input("version", "after")])
    _stdout, _stderr, status = reconcile(
      changed,
      environment: fault_environment(rollback_unlink: true),
    )
    assert(status.success?, "fault setup did not leave a committed record")
    assert_equal(1, rollback_artifacts.length)
    reconcile!(changed)
    assert_equal([], rollback_artifacts)
  end

  def same_producer_observations_hash_under_lock
    observed = File.join(@root, "observed")
    File.write(observed, "old")
    input = manifest([path_input("observed", @root, "observed")])
    ready = File.join(@root, "old-observation-ready")
    release = File.join(@root, "release-old-observation")
    wrapper = File.join(@root, "block-input-read.rb")
    File.write(wrapper, <<~RUBY)
      class << File
        alias_method :publisher_original_open_for_observation, :open

        def open(path, *arguments, **options, &block)
          return publisher_original_open_for_observation(path, *arguments, **options, &block) unless
            path == ENV["PUBLISHER_BLOCKED_INPUT"] && block

          publisher_original_open_for_observation(path, *arguments, **options) do |file|
            publisher_original_open_for_observation(
              ENV.fetch("PUBLISHER_OBSERVATION_READY"), "wb"
            ) { |marker| marker.write("ready") }
            sleep 0.01 until File.exist?(ENV.fetch("PUBLISHER_OBSERVATION_RELEASE"))
            block.call(file)
          end
        end
      end
    RUBY
    command = [
      COMMAND, "reconcile",
      "--producer", "test-producer",
      "--classification", "reload",
      "--reason", "resources changed",
      "--manifest", input,
    ]
    base_environment = {"HOME" => @home, "XDG_STATE_HOME" => @state}
    old_stdout = File.join(@root, "old.stdout")
    old_stderr = File.join(@root, "old.stderr")
    old_pid = Process.spawn(
      base_environment.merge(
        "PUBLISHER_BLOCKED_INPUT" => observed,
        "PUBLISHER_OBSERVATION_READY" => ready,
        "PUBLISHER_OBSERVATION_RELEASE" => release,
        "RUBYOPT" => "-r#{wrapper}",
      ),
      *command,
      out: old_stdout,
      err: old_stderr,
    )
    500.times do
      break if File.exist?(ready)
      sleep 0.01
    end
    assert(File.exist?(ready), "old observation did not reach the controlled input read")

    replacement = File.join(@root, "observed.new")
    File.write(replacement, "new")
    File.rename(replacement, observed)
    reconcile!(input, producer: "expected-producer")
    expected_generation = generation("reload", "expected-producer")
    new_stdout = File.join(@root, "new.stdout")
    new_stderr = File.join(@root, "new.stderr")
    new_pid = Process.spawn(
      base_environment,
      *command,
      out: new_stdout,
      err: new_stderr,
    )
    500.times do
      break if File.exist?(record_path) && generation == expected_generation
      sleep 0.01
    end
    File.write(release, "release")

    [
      [old_pid, old_stdout, old_stderr],
      [new_pid, new_stdout, new_stderr],
    ].each do |pid, stdout_path, stderr_path|
      _waited_pid, status = Process.wait2(pid)
      output = File.read(stderr_path) + File.read(stdout_path)
      assert(status.success?, "concurrent publisher failed: #{output}")
    end

    assert_equal(
      expected_generation,
      generation,
      "a stale pre-lock observation replaced the current generation",
    )
  ensure
    Process.kill("TERM", old_pid) if old_pid && process_running?(old_pid)
    Process.kill("TERM", new_pid) if new_pid && process_running?(new_pid)
  end

  def process_running?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  end

  def readers_never_observe_partial_json
    reconcile!(manifest([value_input("counter", "0")]))
    reader = fork do
      begin
        2_000.times { JSON.parse(File.binread(record_path)) }
        exit! 0
      rescue StandardError
        exit! 1
      end
    end
    30.times do |index|
      reconcile!(manifest([value_input("counter", index.to_s)]))
    end
    _pid, status = Process.wait2(reader)
    assert(status.success?, "reader observed partial JSON")
  end
end

PublisherTest.new.run
