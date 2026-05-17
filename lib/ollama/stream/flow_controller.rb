# frozen_string_literal: true

module Ollama
  module Stream
    # Handles backpressure and flow control for Ollama streams.
    class FlowController
      attr_reader :max_queue_size

      def initialize(max_queue_size: 1000)
        @max_queue_size = max_queue_size
        @paused = false
      end

      def pause!
        @paused = true
      end

      def resume!
        @paused = false
      end

      def paused?
        @paused
      end

      def wait_if_paused!
        sleep 0.01 while @paused
      end
    end
  end
end
