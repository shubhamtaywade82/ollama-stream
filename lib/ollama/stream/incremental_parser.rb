# frozen_string_literal: true

require "json"

module Ollama
  module Stream
    # Incremental NDJSON parser with safe recovery for fragmented chunks.
    #
    # Ollama emits newline-delimited JSON. This parser buffers partial lines
    # across chunks and returns parsed objects only for completed lines.
    # Invalid JSON lines are skipped (not raised) to keep the stream resilient.
    class IncrementalParser
      attr_reader :buffer

      def initialize
        @buffer = +""
      end

      # Append a chunk and return an Array of any complete JSON objects now parseable.
      # Incomplete trailing data stays in the buffer.
      def parse_chunk(chunk)
        return [] if chunk.nil?

        @buffer << chunk.to_s
        results = []

        while (idx = @buffer.index("\n"))
          line = @buffer.slice!(0, idx + 1).chomp
          next if line.strip.empty?

          begin
            results << JSON.parse(line)
          rescue JSON::ParserError
            # Malformed line — drop and continue rather than break the stream.
          end
        end

        results
      end

      # Force-parse any remaining buffered text (call at stream end).
      def flush
        return [] if @buffer.strip.empty?

        leftover = @buffer.dup
        @buffer.clear
        begin
          [JSON.parse(leftover)]
        rescue JSON::ParserError
          []
        end
      end
    end
  end
end
