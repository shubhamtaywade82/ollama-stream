# frozen_string_literal: true

require "securerandom"
require "json"

module Ollama
  module Stream
    # Bidirectional persistent session capabilities for continuous chat over WebSockets.
    class WebSocketSession
      attr_reader :client, :session_id, :history

      def initialize(client)
        @client = client
        @session_id = SecureRandom.hex(16)
        @history = []
      end

      # Receives a WebSocket JSON message, updates history, and returns a StreamObject.
      # @param json_message [String]
      # @return [Ollama::Stream::StreamObject]
      def receive_message(json_message)
        data = JSON.parse(json_message)
        model = data["model"] || "llama3"
        prompt = data["prompt"] || data["content"]
        @history << { role: "user", content: prompt }

        StreamObject.new(@client, model: model, messages: @history)
      end

      def append_assistant(content)
        @history << { role: "assistant", content: content }
      end
    end
  end
end
