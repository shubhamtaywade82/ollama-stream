# frozen_string_literal: true

# Live integration: drive a real Ollama chat through StreamObject + RackAdapter.
# Excluded by default; run with: INTEGRATION=1 bundle exec rspec spec/integration

require "ollama_client"

RSpec.describe "Ollama::Stream live", :integration do
  before do
    reason = IntegrationHelper.skip_reason(requires_chat: true)
    skip(reason) if reason
  end

  let(:client) do
    Ollama::Client.new(config: Ollama::Config.new.tap { |c| c.base_url = IntegrationHelper::OLLAMA_URL })
  end
  let(:model) { IntegrationHelper.chat_model }

  it "StreamObject yields tokens until completion" do
    stream = Ollama::Stream::StreamObject.new(
      client, model: model,
      messages: [{ role: "user", content: "Reply with: ok" }]
    )
    tokens = []
    stream.each_token { |t| tokens << t }
    expect(tokens.length).to be > 0
    expect(stream.status).to eq(:completed)
  end

  it "RackAdapter returns SSE body terminated by [DONE]" do
    adapter = Ollama::Stream::RackAdapter.new(client, model: model)
    status, headers, body = adapter.call({ "QUERY_STRING" => "prompt=Say%20ok" })

    expect(status).to eq(200)
    expect(headers["Content-Type"]).to eq("text/event-stream")

    chunks = []
    body.each { |c| chunks << c }
    expect(chunks.last).to eq("data: [DONE]\n\n")
  end
end
