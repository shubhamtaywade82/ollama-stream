# frozen_string_literal: true

require "json"

module Ollama
  module Stream
    # Advanced incremental parser for safe recovery of malformed JSON chunks.
    class IncrementalParser
      attr_reader :buffer

      def initialize
        @buffer = +""
      end

      # Parses a stream chunk, buffering incomplete JSON fragments.
      # @param chunk [String]
      # @return [String, Hash, nil]
      def parse_chunk(chunk)
        return chunk unless chunk.is_a?(String)

        @buffer << chunk
        stripped = @buffer.strip

        if stripped.start_with?("{")
          if stripped.end_with?("}")
            begin
              parsed = JSON.parse(@buffer)
              @buffer.clear
              return parsed
            rescue JSON::ParserError
              # Incomplete JSON, keep buffering
              return nil
            end
          else
            # Incomplete JSON object, keep buffering
            return nil
          end
        end

        # For plain text token streaming, return the chunk directly
        chunk
      end
    end
  end
end
