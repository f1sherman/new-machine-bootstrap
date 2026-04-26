# frozen_string_literal: true

require "json"
require "open3"
require "time"

module LowRiskAutomerge
  class Error < StandardError; end
  class HttpError < Error; end

  ReviewMetadata = Struct.new(:reviewed_head, :risk, :merge_ok, :reviewer, keyword_init: true)

  module MetadataParser
    BLOCK = /<!--\s*codex-review:v1\s*\n(?<body>.*?)\n-->/m
    VALID_RISKS = %w[low medium high unknown].freeze

    def self.parse(comment_body)
      matches = comment_body.to_s.scan(BLOCK)
      return nil unless matches.length == 1

      fields = {}
      matches.first.first.each_line do |line|
        key, value = line.strip.split(":", 2)
        return nil unless key && value

        key = key.strip
        value = value.strip
        return nil if fields.key?(key)

        fields[key] = value
      end

      risk = fields["risk"]
      merge_ok = fields["merge_ok"]
      return nil unless VALID_RISKS.include?(risk)
      return nil unless %w[true false].include?(merge_ok)
      return nil if fields["reviewed_head"].to_s.empty?
      return nil unless fields["reviewer"] == "codex-pr-review"

      ReviewMetadata.new(
        reviewed_head: fields.fetch("reviewed_head"),
        risk: risk,
        merge_ok: merge_ok == "true",
        reviewer: fields.fetch("reviewer")
      )
    end
  end
end
