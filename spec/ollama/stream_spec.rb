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

    it "blocks on push when bounded queue is full and releases on pop" do
      fc = described_class.new(max_queue_size: 2)
      fc.push(:a)
      fc.push(:b)

      pushed = false
      t = Thread.new do
        fc.push(:c)
        pushed = true
      end

      sleep 0.05
      expect(pushed).to be false
      expect(fc.pop).to eq(:a)
      t.join(0.5)
      expect(pushed).to be true
      fc.close
    end

    it "wait_if_paused! blocks until resumed" do
      fc = described_class.new
      fc.pause!

      resumed = false
      t = Thread.new do
        fc.wait_if_paused!
        resumed = true
      end

      sleep 0.05
      expect(resumed).to be false
      fc.resume!
      t.join(0.5)
      expect(resumed).to be true
    end
  end

  describe Ollama::Stream::IncrementalParser do
    it "parses single complete JSON object" do
      parser = described_class.new
      expect(parser.parse_chunk(%({"a":1}\n))).to eq([{ "a" => 1 }])
    end

    it "buffers and parses split JSON object across chunks" do
      parser = described_class.new
      expect(parser.parse_chunk(%({"a": ))).to eq([])
      expect(parser.parse_chunk(%(1}\n))).to eq([{ "a" => 1 }])
    end

    it "parses NDJSON (newline-delimited JSON) chunks" do
      parser = described_class.new
      out = parser.parse_chunk(%({"a":1}\n{"b":2}\n))
      expect(out).to eq([{ "a" => 1 }, { "b" => 2 }])
    end

    it "handles split-across-newline NDJSON" do
      parser = described_class.new
      expect(parser.parse_chunk(%({"a":1}\n{"b":))).to eq([{ "a" => 1 }])
      expect(parser.parse_chunk(%(2}\n))).to eq([{ "b" => 2 }])
    end

    it "skips blank lines" do
      parser = described_class.new
      expect(parser.parse_chunk("\n\n")).to eq([])
    end
  end

  describe Ollama::Stream::StreamObject do
    let(:client) { instance_double(Ollama::Client) }

    def fake_chat_with(events)
      allow(client).to receive(:chat) do |args|
        hooks = args[:hooks]
        events.each do |type, payload|
          case type
          when :token then hooks[:on_token].call(payload, nil)
          when :tool then hooks[:on_tool_call].call(payload)
          when :error then hooks[:on_error].call(payload); break
          end
        end
        hooks[:on_complete].call
      end
    end

    it "yields tokens until complete" do
      fake_chat_with([[:token, "Hello"], [:token, " world"]])
      stream = described_class.new(client, model: "m", messages: [])
      tokens = []
      stream.each_token { |t| tokens << t }
      expect(tokens).to eq(["Hello", " world"])
      expect(stream.status).to eq(:completed)
    end

    it "yields tool calls" do
      fake_chat_with([[:tool, { name: "x", arguments: {} }]])
      stream = described_class.new(client, model: "m", messages: [])
      events = []
      stream.each_token { |t| events << t }
      expect(events.first).to eq({ name: "x", arguments: {} })
    end

    it "raises on error events" do
      err = StandardError.new("boom")
      fake_chat_with([[:error, err]])
      stream = described_class.new(client, model: "m", messages: [])
      expect { stream.each_token { |_| } }.to raise_error(StandardError, "boom")
      expect(stream.status).to eq(:error)
    end

    it "cancels mid-stream" do
      fake_chat_with(Array.new(20) { |i| [:token, "t#{i}"] })
      stream = described_class.new(client, model: "m", messages: [])
      tokens = []
      stream.each_token do |t|
        tokens << t
        stream.cancel if tokens.length == 3
      end
      expect(tokens.length).to be < 20
      expect(stream.status).to eq(:cancelled)
    end
  end

  describe Ollama::Stream::WebSocketSession do
    let(:client) { instance_double(Ollama::Client) }

    it "appends user message and creates stream object" do
      session = described_class.new(client)
      stream = session.receive_message({ model: "llama3", prompt: "Hi" }.to_json)
      expect(stream).to be_a(Ollama::Stream::StreamObject)
      expect(session.history.last[:content]).to eq("Hi")
    end

    it "appends assistant reply to history" do
      session = described_class.new(client)
      session.append_assistant("Sure thing")
      expect(session.history.last).to eq({ role: "assistant", content: "Sure thing" })
    end

    it "exposes a stable session id" do
      session = described_class.new(client)
      expect(session.session_id).to match(/\A[a-f0-9]{32}\z/)
    end
  end

  describe Ollama::Stream::RackAdapter do
    let(:client) { instance_double(Ollama::Client) }

    it "returns rack response with SSE headers" do
      allow(client).to receive(:chat) { |args| args[:hooks][:on_complete].call }
      adapter = described_class.new(client)
      status, headers, body = adapter.call({ "QUERY_STRING" => "prompt=Hello" })
      expect(status).to eq(200)
      expect(headers["Content-Type"]).to eq("text/event-stream")
      expect(body).to respond_to(:each)
    end

    it "streams tokens through SSE body" do
      allow(client).to receive(:chat) do |args|
        args[:hooks][:on_token].call("Hi", nil)
        args[:hooks][:on_complete].call
      end

      adapter = described_class.new(client)
      _, _, body = adapter.call({ "QUERY_STRING" => "prompt=x" })
      chunks = []
      body.each { |c| chunks << c }
      expect(chunks.first).to include("data:")
      expect(chunks.first).to include("Hi")
      expect(chunks.last).to eq("data: [DONE]\n\n")
    end
  end
end
