# frozen_string_literal: true

RSpec.describe Duva::Address do
  describe ".format" do
    it "returns the bare address without a name" do
      expect(described_class.format("a@example.com")).to eq("a@example.com")
    end

    it "wraps a name around the address" do
      expect(described_class.format("a@example.com", "Example")).to eq("Example <a@example.com>")
    end

    it "quotes and escapes a name containing a comma or a quote" do
      expect(described_class.format("a@example.com", 'Some, "Name"')).to eq('"Some, \"Name\"" <a@example.com>')
    end
  end

  describe ".unsubscribe_headers" do
    it "builds both headers for one-click unsubscribe by default" do
      expect(described_class.unsubscribe_headers(https_url: "https://example.com/u")).to eq(
        "List-Unsubscribe" => "<https://example.com/u>",
        "List-Unsubscribe-Post" => "List-Unsubscribe=One-Click"
      )
    end

    it "combines an https link and a mailto without one-click when asked" do
      headers = described_class.unsubscribe_headers(https_url: "https://example.com/u", mailto: "stop@example.com",
                                                    one_click: false)

      expect(headers).to eq("List-Unsubscribe" => "<https://example.com/u>, <mailto:stop@example.com>")
    end

    it "a mailto-only unsubscribe never gets List-Unsubscribe-Post" do
      headers = described_class.unsubscribe_headers(mailto: "stop@example.com")

      expect(headers).to eq("List-Unsubscribe" => "<mailto:stop@example.com>")
    end

    it "raises without any destination" do
      expect { described_class.unsubscribe_headers }.to raise_error(ArgumentError, /needs https_url/)
    end

    it "raises if https_url is not https" do
      expect { described_class.unsubscribe_headers(https_url: "http://example.com/u") }.to raise_error(ArgumentError, %r{https://})
    end

    it "raises asking for one-click without an https link" do
      expect do
        described_class.unsubscribe_headers(mailto: "stop@example.com",
                                            one_click: true)
      end.to raise_error(ArgumentError, /needs https_url/)
    end
  end
end
