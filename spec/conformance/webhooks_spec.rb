# frozen_string_literal: true

require "json"
require "time"

WEBHOOKS_FIXTURE_PATH = File.expand_path("../../conformance/webhooks.json", __dir__)

RSpec.describe "Duva::Webhooks against duva-mail/duva-conformance", if: File.exist?(WEBHOOKS_FIXTURE_PATH) do
  fixture = JSON.parse(File.read(WEBHOOKS_FIXTURE_PATH))
  # A webhook signature expires by design (replay protection): it can only be replayed by
  # freezing the clock at the fixture's `reference_now`, never at the real wall-clock time.
  now = Time.iso8601(fixture["reference_now"]).to_i
  non_rotation = fixture["cases"].reject { |c| c["category"] == "rotation" }

  non_rotation.each do |test_case|
    it test_case["name"] do
      # Always its OWN secret (the fixture's canonical one); `signed_with` is informational
      # only: it's exactly what a `wrong_secret` case distinguishes.
      got = Duva::Webhooks.verify_signature(fixture["secret"], test_case["headers"], test_case["body"],
                                            tolerance_seconds: fixture["tolerance_seconds"], now: now)

      expect(got).to eq(test_case["expect"])
    end
  end

  it "covers every non-rotation case" do
    expect(non_rotation.length).to eq(fixture["cases"].length - 1)
  end

  rotation = fixture["cases"].find { |c| c["category"] == "rotation" }

  it "a rotation vector verifies against a LIST of active secrets" do
    expect(rotation).not_to be_nil
    # The active set during rotation: the current secret (`other_valid_secret`, == the
    # top-level `secret`) AND the older one that actually signed this webhook (`signed_with`).
    secrets = [rotation["other_valid_secret"], rotation["signed_with"]]
    got = Duva::Webhooks.verify_signature(secrets, rotation["headers"], rotation["body"],
                                          tolerance_seconds: fixture["tolerance_seconds"], now: now)

    expect(got).to eq(rotation["expect"])
  end

  it "the current secret alone is NOT enough (proof the case truly needs the older one too)" do
    with_current_only = Duva::Webhooks.verify_signature(rotation["other_valid_secret"], rotation["headers"], rotation["body"],
                                                        now: now)
    expect(with_current_only).to be(false)

    # The point: a verifier must try it too, it doesn't know which one signed.
    with_the_signer_alone = Duva::Webhooks.verify_signature(rotation["signed_with"], rotation["headers"], rotation["body"],
                                                            now: now)
    expect(with_the_signer_alone).to be(true)
  end
end

RSpec.describe "conformance/webhooks.json" do
  it "is available (run script/fetch_conformance.rb otherwise)", skip: !File.exist?(WEBHOOKS_FIXTURE_PATH) do
    expect(File.exist?(WEBHOOKS_FIXTURE_PATH)).to be(true)
  end
end
