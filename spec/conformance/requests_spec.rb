# frozen_string_literal: true

require "json"

REQUESTS_FIXTURE_PATH = File.expand_path("../../conformance/requests.json", __dir__)

CALL = {
  "sendMessage" => lambda do |duva, input|
    duva.messages.deliver(from: input["from_"], to: input["to"], subject: input["subject"], text: input["text"],
                          tags: input["tags"], metadata: input["metadata"], idempotency_key: input["idempotency_key"])
  end,
  "addSuppression" => ->(duva, input) { duva.suppressions.add(input["email"]) },
  "createWebhook" => ->(duva, input) { duva.webhooks.create(input["url"], events: input["events"]) },
  "getMessage" => ->(duva, input) { duva.messages.get(input["id"]) },
  "removeSuppression" => ->(duva, input) { duva.suppressions.remove(input["email"]) }
}.freeze

RSpec.describe "requests built against duva-mail/duva-conformance", if: File.exist?(REQUESTS_FIXTURE_PATH) do
  fixture = JSON.parse(File.read(REQUESTS_FIXTURE_PATH))

  fixture["cases"].each do |test_case|
    it test_case["operation_id"] do
      config = Duva::Config.resolve(api_key: test_case["input"]["api_key"], domain: test_case["input"]["domain"],
                                    base_url: "https://api.example.com")
      captured = nil
      transport = Duva::TestTransport.new do |cfg, spec|
        captured = Duva::HttpMessage.build(cfg, spec)
        Duva::TestTransport.response({ "id" => "x", "status" => "queued", "data" => [] })
      end
      duva = Duva::Client.new(api_key: config.api_key, domain: config.domain, base_url: config.base_url, transport: transport)

      begin
        CALL.fetch(test_case["operation_id"]).call(duva, test_case["input"])
      rescue StandardError
        # See TestTransport's fake response above: only the request that was SENT matters here,
        # a downstream model-parsing mismatch against this generic body is not this test's concern.
      end

      expected = test_case["expected_request"]
      expect(captured[:method]).to eq(expected["method"])
      expect(captured[:uri].path).to eq(expected["path"])
      expected["headers"].each { |name, value| expect(captured[:headers][name]).to eq(value) }
      if expected["body"].nil?
        expect(captured[:body]).to be_nil
      else
        expect(JSON.parse(captured[:body])).to eq(expected["body"])
      end
    end
  end

  it "covers every operation the generator declares" do
    missing = fixture["cases"].map { |c| c["operation_id"] }.reject { |id| CALL.key?(id) }
    expect(missing).to eq([])
  end
end

RSpec.describe "conformance/requests.json" do
  it "is available (run script/fetch_conformance.rb otherwise)", skip: !File.exist?(REQUESTS_FIXTURE_PATH) do
    expect(File.exist?(REQUESTS_FIXTURE_PATH)).to be(true)
  end
end
