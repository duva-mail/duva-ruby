# frozen_string_literal: true

require "base64"

RSpec.describe Duva::Attachments do
  describe ".from_bytes" do
    it "base64-encodes the bytes and defaults content_type/content_id to nil" do
      attachment = described_class.from_bytes("a.txt", "hi")

      expect(attachment.to_h).to eq(
        "filename" => "a.txt", "content" => Base64.strict_encode64("hi"), "content_type" => nil, "content_id" => nil
      )
    end

    it "carries an explicit content type and inline content id" do
      attachment = described_class.from_bytes("logo.png", [1, 2, 3].pack("C*"), content_type: "image/png", content_id: "logo")

      expect(attachment.content_type).to eq("image/png")
      expect(attachment.content_id).to eq("logo")
    end

    it "refuses a filename with a path" do
      expect { described_class.from_bytes("../a.txt", "") }.to raise_error(ArgumentError, /path/)
    end

    it "refuses an executable extension" do
      expect { described_class.from_bytes("virus.exe", "") }.to raise_error(ArgumentError, /executable/)
    end
  end

  describe ".assert_limits" do
    it "accepts a message within the limits" do
      attachments = [described_class.from_bytes("a.txt", "hi")]

      expect { described_class.assert_limits(attachments) }.not_to raise_error
    end

    it "refuses more than 10 attachments" do
      attachments = Array.new(11) { |i| described_class.from_bytes("a#{i}.txt", "") }

      expect { described_class.assert_limits(attachments) }.to raise_error(ArgumentError, /at most 10/)
    end

    it "refuses more than 5 MB decoded in total" do
      big = described_class.from_bytes("big.bin", "\x00" * ((5 * 1024 * 1024) + 1))

      expect { described_class.assert_limits([big]) }.to raise_error(ArgumentError, /limit/)
    end
  end
end
