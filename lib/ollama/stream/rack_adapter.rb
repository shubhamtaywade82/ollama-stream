# frozen_string_literal: true

require "uri"
require "json"

module Ollama
  module Stream
    # Rack-compatible stream adapter for easy proxying from Ollama through a Ruby backend.
    class RackAdapter
      attr_reader :client, :model

      def initialize(client, model: "llama3")
        @client = client
        @model = model
      end

      # Rack call interface. Parses query params and returns an SSE stream.
      # @param env [Hash] Rack environment
      def call(env)
        query = env["QUERY_STRING"].to_s
        prompt_param = query.split("&").find { |p| p.start_with?("prompt=") }
        prompt_val = prompt_param ? prompt_param.split("prompt=").last : "Hello"
        prompt = URI.decode_www_form_component(prompt_val)

        messages = [{ role: "user", content: prompt }]
        stream_obj = StreamObject.new(@client, model: @model, messages: messages)

        headers = {
          "Content-Type" => "text/event-stream",
          "Cache-Control" => "no-cache",
          "Connection" => "keep-alive"
        }

        body = Enumerator.new do |yielder|
          stream_obj.each_token do |token|
            yielder << "data: #{token.to_json}\n\n"
          end
          yielder << "data: [DONE]\n\n"
        end

        [200, headers, body]
      end
    end
  end
end
