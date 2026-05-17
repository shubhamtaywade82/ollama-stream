# frozen_string_literal: true

require "ollama_client"
require_relative "stream/version"
require_relative "stream/flow_controller"
require_relative "stream/incremental_parser"
require_relative "stream/stream_object"
require_relative "stream/websocket_session"
require_relative "stream/rack_adapter"

module Ollama
  module Stream
    class Error < StandardError; end
  end
end
