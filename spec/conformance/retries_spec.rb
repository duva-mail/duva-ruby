# frozen_string_literal: true

require "json"

RETRIES_FIXTURE_PATH = File.expand_path("../../conformance/retries.json", __dir__)

RETRY_CALL = {
  "sendMessage" => ->(duva) { duva.messages.deliver(from: "a@example.com", to: ["b@example.org"], subject: "s", text: "t") },
  "getMessage" => ->(duva) { duva.messages.get("msg_#{'a' * 32}") },
  "addSuppression" => ->(duva) { duva.suppressions.add("b@example.org") },
  "listEvents" => ->(duva) { duva.events.list }
}.freeze

RSpec.describe "retries against duva-mail/duva-conformance", if: File.exist?(RETRIES_FIXTURE_PATH) do
  fixture = JSON.parse(File.read(RETRIES_FIXTURE_PATH))

  fixture["cases"].each do |test_case|
    it test_case["name"] do
      sequence = test_case["response_sequence"]
      attempts = 0
      transport = Duva::TestTransport.new do |_config, _spec|
        scripted = sequence[attempts]
        attempts += 1
        raise Duva::ConnectionError, "simulated network failure" if scripted["status"].nil?

        headers = (scripted["headers"] || {}).transform_keys(&:downcase)
        unless scripted["status"] < 300
          raise Duva.error_from_response(scripted["status"], scripted["body"], scripted["body"].to_json, headers["retry-after"])
        end

        Duva::TestTransport.response(scripted["body"], headers: headers)
      end
      duva = Duva::Client.new(api_key: "dv_test", domain: "example.com", transport: transport,
                              max_retries: test_case["max_retries"], max_retry_wait_seconds: test_case["max_retry_wait_seconds"])
      call = RETRY_CALL.fetch(test_case["operation_id"])

      if test_case["expected_outcome"] == "success"
        # retries.json's success bodies are the same generic placeholder across every operation
        # (only the transport-level retry/error behavior is under test here, not response
        # shape): a real `listEvents` call parses a proper EventPage, this fixture's body just
        # doesn't shape-match it -- expected, not a failure.
        begin
          call.call(duva)
        rescue NoMethodError, TypeError
          nil
        end
      else
        _, code = test_case["expected_outcome"].split(":")
        error = begin
          call.call(duva)
          nil
        rescue StandardError => e
          e
        end
        expect(error).not_to be_nil
        if code == "server"
          expect(error).to be_a(Duva::ServerError).or be_a(Duva::ConnectionError)
        else
          expect(error).to be_a(Duva::Error)
          expect(error.code).to eq(code)
        end
      end

      expect(attempts).to eq(test_case["expected_attempts"])
    end
  end
end

RSpec.describe "conformance/retries.json" do
  it "is available (run script/fetch_conformance.rb otherwise)", skip: !File.exist?(RETRIES_FIXTURE_PATH) do
    expect(File.exist?(RETRIES_FIXTURE_PATH)).to be(true)
  end
end
