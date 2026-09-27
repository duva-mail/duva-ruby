# frozen_string_literal: true

RSpec.describe "Duva.error_from_response" do
  it "maps each documented code to its class" do
    cases = [
      ["unauthorized", 401, Duva::AuthenticationError],
      ["not_found", 404, Duva::NotFoundError],
      ["domain_not_verified", 403, Duva::PermissionError],
      ["sending_not_allowed", 403, Duva::PermissionError],
      ["idempotency_conflict", 409, Duva::ConflictError],
      ["limit_reached", 409, Duva::ConflictError],
      ["invalid_request", 422, Duva::ValidationError],
      ["internal_error", 500, Duva::ServerError]
    ]
    cases.each do |code, status, klass|
      error = Duva.error_from_response(status, { "error" => { "code" => code, "message" => "x" } }, "{}", nil)
      expect(error).to be_a(klass)
      expect(error.code).to eq(code)
      expect(error.status).to eq(status)
    end
  end

  it "carries retry_after for quota_exceeded and rate_limited, and only those" do
    quota = Duva.error_from_response(429, { "error" => { "code" => "quota_exceeded", "message" => "x" } }, "{}", "3600")
    expect(quota).to be_a(Duva::QuotaExceededError)
    expect(quota.retry_after).to eq(3600)

    rate = Duva.error_from_response(429, { "error" => { "code" => "rate_limited", "message" => "x" } }, "{}", "5")
    expect(rate).to be_a(Duva::RateLimitError)
    expect(rate.retry_after).to eq(5)
  end

  it "carries field errors on invalid_request" do
    body = { "error" => { "code" => "invalid_request", "message" => "x",
                          "fields" => [{ "field" => "to[0]", "message" => "bad" }] } }
    error = Duva.error_from_response(422, body, "{}", nil)

    expect(error.fields).to eq([{ "field" => "to[0]", "message" => "bad" }])
  end

  it "never crashes on a body that is not the documented envelope" do
    error = Duva.error_from_response(502, "<html>bad gateway</html>", "<html>bad gateway</html>", nil)

    expect(error).to be_a(Duva::ServerError)
    expect(error.code).to eq("http_error")
  end

  it "bounds the raw body it keeps" do
    huge = "x" * 10_000
    error = Duva.error_from_response(500, nil, huge, nil)

    expect(error.raw_body.length).to be <= 4096
  end

  it "falls back to ServerError for an unknown code, rather than crashing" do
    error = Duva.error_from_response(599, { "error" => { "code" => "something_new", "message" => "x" } }, "{}", nil)

    expect(error).to be_a(Duva::ServerError)
    expect(error.code).to eq("something_new")
  end

  it "never leaks the raw body through #inspect" do
    error = Duva.error_from_response(500, nil, "sensitive detail", nil)

    expect(error.inspect).not_to include("sensitive detail")
  end
end
