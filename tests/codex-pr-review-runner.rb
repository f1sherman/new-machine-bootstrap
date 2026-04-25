#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "pathname"
require "tmpdir"

require_relative "../tools/codex-pr-review/review_runner"

module CodexPrReview
  class ReviewRunnerTrustBoundaryTest < Minitest::Test
    SuccessStatus = Struct.new(:success?)

    class TestRunner < ReviewRunner
      def initialize(*args, rubric_source:, schema_source:, **kwargs)
        super(*args, **kwargs)
        @rubric_source = Pathname.new(rubric_source)
        @schema_source = Pathname.new(schema_source)
      end

      private

      def rubric_source_path
        @rubric_source
      end

      def schema_source_path
        @schema_source
      end
    end

    def setup
      @tmpdir = Dir.mktmpdir("codex-pr-review-runner-test")
      @output_dir = Pathname.new(@tmpdir).join("output")
      @rubric_source = Pathname.new(@tmpdir).join("rubric.md")
      @schema_source = Pathname.new(@tmpdir).join("schema.json")
      @review_output_path = @output_dir.join("codex-review.json")
      File.write(@rubric_source, "trusted rubric")
      File.write(@schema_source, "{\"type\":\"object\"}\n")
      @runner = TestRunner.new(
        platform: "github",
        repo: "f1sherman/new-machine-bootstrap",
        pr_number: 95,
        output_dir: @output_dir,
        rubric_source: @rubric_source,
        schema_source: @schema_source
      )
      @saved_env = ENV.to_h.slice("GITHUB_TOKEN", "CODEX_AUTH_JSON", "FORGEJO_TOKEN", "FORGEJO_BOT_TOKEN")
      ENV["GITHUB_TOKEN"] = "github-secret"
      ENV["CODEX_AUTH_JSON"] = "{\"token\":\"codex-secret\"}"
      ENV["FORGEJO_TOKEN"] = "forgejo-secret"
      ENV["FORGEJO_BOT_TOKEN"] = "forgejo-bot-secret"
    end

    def teardown
      ENV.delete("GITHUB_TOKEN")
      ENV.delete("CODEX_AUTH_JSON")
      ENV.delete("FORGEJO_TOKEN")
      ENV.delete("FORGEJO_BOT_TOKEN")
      @saved_env.each { |key, value| ENV[key] = value }
      FileUtils.rm_rf(@tmpdir)
    end

    def test_prepare_trusted_codex_assets_copies_schema_and_rubric
      trusted_assets = @runner.send(:prepare_trusted_codex_assets)

      File.write(@rubric_source, "attacker rubric")
      File.write(@schema_source, "{\"type\":\"string\"}\n")

      assert_equal "trusted rubric", trusted_assets.fetch(:rubric_text)
      assert_equal "{\"type\":\"object\"}\n", trusted_assets.fetch(:schema_path).read
      refute_equal @schema_source, trusted_assets.fetch(:schema_path)
    end

    def test_run_codex_uses_scrubbed_environment_and_supplied_schema_path
      trusted_assets = @runner.send(:prepare_trusted_codex_assets)
      capture = nil
      output_dir = @output_dir
      review_output_path = @review_output_path

      with_capture3_stub(
        lambda do |*args, **kwargs|
          capture = { args: args, kwargs: kwargs }
          FileUtils.mkdir_p(output_dir)
          File.write(review_output_path, <<~JSON)
            {"findings":[],"overall_correctness":"patch is correct","overall_confidence_score":0.92,"overall_explanation":"ok"}
          JSON
          ["", "", SuccessStatus.new(true)]
        end
      ) do
        @runner.send(:run_codex, "review prompt", schema_path: trusted_assets.fetch(:schema_path))
      end

      env = capture.fetch(:args).first
      argv = capture.fetch(:args).drop(1)

      assert_nil env["GITHUB_TOKEN"]
      assert_nil env["CODEX_AUTH_JSON"]
      assert_nil env["FORGEJO_TOKEN"]
      assert_nil env["FORGEJO_BOT_TOKEN"]
      assert_includes argv.each_cons(2).to_a, ["--output-schema", trusted_assets.fetch(:schema_path).to_s]
      assert_equal ReviewRunner::REPO_ROOT.to_s, capture.fetch(:kwargs).fetch(:chdir)
      assert_equal "review prompt", capture.fetch(:kwargs).fetch(:stdin_data)
    end

    private

    def with_capture3_stub(replacement)
      singleton = Open3.singleton_class
      singleton.alias_method(:__codex_pr_review_original_capture3, :capture3)
      singleton.define_method(:capture3, &replacement)
      yield
    ensure
      singleton.alias_method(:capture3, :__codex_pr_review_original_capture3)
      singleton.remove_method(:__codex_pr_review_original_capture3)
    end
  end
end
