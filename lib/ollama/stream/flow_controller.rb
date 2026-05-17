# frozen_string_literal: true

require "thread"

module Ollama
  module Stream
    # Backpressure and flow control primitive for streaming pipelines.
    #
    # Pause/resume blocks `wait_if_paused!` callers using a Mutex+ConditionVariable
    # (no busy loops). A bounded SizedQueue gives producers natural backpressure:
    # `push` blocks once `max_queue_size` is reached until a consumer calls `pop`.
    class FlowController
      attr_reader :max_queue_size

      def initialize(max_queue_size: 1000)
        @max_queue_size = max_queue_size
        @queue = SizedQueue.new(max_queue_size)
        @paused = false
        @mutex = Mutex.new
        @cond = ConditionVariable.new
      end

      def pause!
        @mutex.synchronize { @paused = true }
      end

      def resume!
        @mutex.synchronize do
          @paused = false
          @cond.broadcast
        end
      end

      def paused?
        @mutex.synchronize { @paused }
      end

      def wait_if_paused!
        @mutex.synchronize do
          @cond.wait(@mutex) while @paused
        end
      end

      def push(item)
        @queue.push(item)
      end

      def pop
        @queue.pop
      end

      def size
        @queue.size
      end

      def close
        @queue.close
      end
    end
  end
end
