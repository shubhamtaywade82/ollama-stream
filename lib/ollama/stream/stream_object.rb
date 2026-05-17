# frozen_string_literal: true

require "thread"

module Ollama
  module Stream
    # Formal stream wrapper over an Ollama chat call.
    #
    # Runs `client.chat` on a producer thread that pushes events into a
    # bounded queue. The consumer (`each_token`) pulls events on the caller's
    # thread, giving you natural backpressure (producer blocks when the queue
    # is full) plus pause/cancel semantics that work mid-stream.
    #
    # Event tuples on the queue:
    #   [:token, String]
    #   [:thought, String]
    #   [:tool_call, Hash]
    #   [:error, Exception]
    #   [:complete]
    class StreamObject
      SENTINEL = :__ollama_stream_done__

      attr_reader :client, :model, :messages, :options, :status, :flow_controller, :incremental_parser

      def initialize(client, model:, messages:, options: {}, flow_controller: nil, incremental_parser: nil)
        @client = client
        @model = model
        @messages = messages
        @options = options
        @flow_controller = flow_controller || FlowController.new
        @incremental_parser = incremental_parser || IncrementalParser.new
        @status = :idle
        @cancelled = false
      end

      def each_token(&block)
        return enum_for(:each_token) unless block

        @status = :running
        @cancelled = false
        producer = start_producer

        begin
          loop do
            @flow_controller.wait_if_paused!
            if @cancelled
              @status = :cancelled
              break
            end

            event = @flow_controller.pop
            break if event == SENTINEL

            type, payload = event
            case type
            when :token, :thought
              block.call(payload)
            when :tool_call
              block.call(payload)
            when :error
              @status = :error
              raise payload
            when :complete
              @status = :completed
              break
            end
          end
        ensure
          producer.kill if producer.alive?
          @flow_controller.close
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
        @cancelled = true
        @flow_controller.resume! if @flow_controller.paused?
        @flow_controller.push(SENTINEL) rescue nil
      end

      private

      def start_producer
        Thread.new do
          hooks = {
            on_token:     ->(text, _lp = nil) { @flow_controller.push([:token, text]) unless @cancelled },
            on_thought:   ->(text)            { @flow_controller.push([:thought, text]) unless @cancelled },
            on_tool_call: ->(tc)              { @flow_controller.push([:tool_call, tc]) unless @cancelled },
            on_error:     ->(err)             { @flow_controller.push([:error, err]) },
            on_complete:  ->                  { @flow_controller.push([:complete, nil]) }
          }

          begin
            @client.chat(model: @model, messages: @messages, options: @options, hooks: hooks)
          rescue StandardError => e
            @flow_controller.push([:error, e]) rescue nil
          end
        end
      end
    end
  end
end
