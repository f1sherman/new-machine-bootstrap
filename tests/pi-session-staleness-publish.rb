#!/usr/bin/env ruby

require "fileutils"
require "json"
require "open3"
require "tmpdir"

COMMAND = File.expand_path("../roles/common/files/bin/pi-session-staleness-publish", __dir__)
CASES = [
  :stable_directory_order,
  :file_content_change,
  :symlink_target_change,
  :executable_bit_change,
  :missing_path_change,
  :value_change,
  :no_op_preserves_bytes_and_mtime,
  :classification_updates_are_independent,
  :producer_records_are_independent,
  :invalid_operation,
  :invalid_identifier,
  :invalid_classification,
  :invalid_reason,
  :invalid_manifest_schema,
  :duplicate_input_name,
  :relative_root,
  :escaping_relative_path,
  :prior_record_survives_hash_failure,
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

  def reconcile(manifest_path, producer: "test-producer", classification: "reload", reason: "resources changed", operation: "reconcile")
    Open3.capture3(
      {"HOME" => @home, "XDG_STATE_HOME" => @state},
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

  def classification_updates_are_independent
    reconcile!(manifest([value_input("reload", "one")]), classification: "reload")
    reload_state = record.fetch("reload")
    reconcile!(manifest([value_input("restart", "one")]), classification: "restart")
    assert_equal(reload_state, record.fetch("reload"))
    assert(record.key?("restart"), "restart state was not added")
  end

  def producer_records_are_independent
    input = manifest([value_input("version", "one")])
    reconcile!(input, producer: "producer-one")
    first_bytes = File.binread(record_path("producer-one"))
    reconcile!(input, producer: "producer-two")
    assert_equal(first_bytes, File.binread(record_path("producer-one")))
    assert(File.file?(record_path("producer-two")), "second producer record missing")
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
