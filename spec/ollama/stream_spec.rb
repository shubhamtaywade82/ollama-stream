# frozen_string_literal: true

RSpec.describe Ollama::Stream do
  it "has a version number" do
    expect(Ollama::Stream::VERSION).not_to be nil
  end

  describe Ollama::Stream::FlowController do
    it "pauses and resumes" do
      fc = described_class.new
      expect(fc.paused?).to be false
      fc.pause!
      expect(fc.paused?).to be true
      fc.resume!
      expect(fc.paused?).to be false
    end
  end

  describe Ollama::Stream::IncrementalParser do
    it "recovers malformed or fragmented json" do
      parser = described_class.new
      expect(parser.parse_chunk("{ \"a\": ")).to be_nil
      expect(parser.parse_chunk("1 }")).to eq({ "a" => 1 })
      expect(parser.parse_chunk("plain text")).to eq("plain text")
    end
  end

  describe Ollama::Stream::WebSocketSession do
    let(:client) { instance_double(Ollama::Client) }

    it "receives message and creates stream object" do
      session = described_class.new(client)
      stream = session.receive_message({ model: "llama3", prompt: "Hi" }.to_json)
      expect(stream).to be_a(Ollama::Stream::StreamObject)
      expect(session.history.last[:content]).to eq("Hi")
    end
  end

  describe Ollama::Stream::RackAdapter do
    let(:client) { instance_double(Ollama::Client) }

    it "returns rack response with SSE body" do
      adapter = described_class.new(client)
      status, headers, body = adapter.call({ "QUERY_STRING" => "prompt=Hello" })
      expect(status).to eq(200)
      expect(headers["Content-Type"]).to eq("text/event-stream")
      expect(body).to be_a(Enumerator)
    end
  end
end
