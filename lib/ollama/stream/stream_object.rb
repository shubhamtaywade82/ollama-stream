# frozen_string_literal: true

require "fiber"

module Ollama
  module Stream
    # Formal stream object encapsulating an Ollama SSE stream.
    class StreamObject
      attr_reader :client, :model, :messages, :options, :status, :flow_controller, :incremental_parser

      def initialize(client, model:, messages:, options: {}, flow_controller: nil, incremental_parser: nil)
        @client = client
        @model = model
        @messages = messages
        @options = options
        @flow_controller = flow_controller || FlowController.new
        @incremental_parser = incremental_parser || IncrementalParser.new
        @status = :idle
        @fiber = nil
      end

      # Yields each token or event from the stream.
      # Supports pause, resume, and cancellation.
      def each_token(&block)
        return enum_for(:each_token) unless block

        @status = :running
        @fiber = Fiber.new do
          hooks = {
            on_token: ->(text, _logprobs = nil) {
              Fiber.yield([:token, text]) if @status == :running
            },
            on_thought: ->(text) {
              Fiber.yield([:thought, text]) if @status == :running
            },
            on_tool_call: ->(tc) {
              Fiber.yield([:tool_call, tc]) if @status == :running
            },
            on_error: ->(err) {
              Fiber.yield([:error, err])
            },
            on_complete: -> {
              Fiber.yield([:complete, nil])
            }
          }

          begin
            @client.chat(model: @model, messages: @messages, options: @options, hooks: hooks)
          rescue StandardError => e
            Fiber.yield([:error, e])
          end
        end

        while @fiber.alive? && @status == :running
          @flow_controller.wait_if_paused!
          break if @status == :cancelled

          event, data = @fiber.resume
          case event
          when :token, :thought
            parsed = @incremental_parser.parse_chunk(data)
            block.call(parsed) if parsed
          when :tool_call
            block.call(data)
          when :error
            @status = :error
            raise data
          when :complete
            @status = :completed
            break
          end
        end
      end

      def pause
        @flow_controller.pause!
        @status = :paused
      end

      def resume
        @flow_controller.resume!
        @status = :running
      end

      def cancel
        @status = :cancelled
      end
    end
  end
end
