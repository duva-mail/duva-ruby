# frozen_string_literal: true

require "base64"
require "json"
require "openssl"

module Duva
  # The JSON body Duva sends to your webhook URL, already parsed.
  WebhookEvent = Data.define(:id, :type, :domain, :data)

  # Webhook signature verification, "Standard Webhooks" format (see `docs/api.md` "Webhooks" in
  # the `duva` repository). Duva SENDS webhooks; this module is for VERIFYING them on your side.
  module Webhooks
    SECRET_PREFIX = "whsec_"
    DEFAULT_TOLERANCE_SECONDS = 300
    private_constant :SECRET_PREFIX, :DEFAULT_TOLERANCE_SECONDS

    class << self
      # Verifies a webhook request. `secrets` accepts one secret or an array (for key rotation:
      # while both the old and the new secret are active, a webhook signed with either must
      # verify).
      #
      # `headers` is looked up case-insensitively (whatever your framework hands you is not
      # guaranteed to have lower-case keys). `raw_body` must be the EXACT bytes Duva sent: re-
      # encoding a parsed-then-re-serialized JSON body changes its bytes and invalidates every
      # signature.
      #
      # `now`: the current instant as a Unix timestamp in seconds. Defaults to `Time.now.to_i`;
      # override only in your OWN tests (see .sign and the fixtures of `duva-mail/duva-conformance`,
      # which document the exact instant each vector was signed at).
      def verify_signature(secrets, headers, raw_body, tolerance_seconds: DEFAULT_TOLERANCE_SECONDS, now: nil)
        event_id = header(headers, "webhook-id")
        timestamp = header(headers, "webhook-timestamp")
        signature_header = header(headers, "webhook-signature")
        return false if event_id.nil? || timestamp.nil? || signature_header.nil? || signature_header.empty?

        at = Integer(timestamp, exception: false)
        return false if at.nil?

        current = now || Time.now.to_i
        return false if (current - at).abs > tolerance_seconds

        secret_list = secrets.is_a?(Array) ? secrets : [secrets]
        expected = expected_signatures(secret_list, event_id, timestamp, raw_body)
        return false if expected.nil?

        # `webhook-signature` may carry several space-separated `v1,<signature>` entries (Duva
        # sends one; a sender that itself rotates its OWN signing key mid-flight could send
        # more): any match against any of your active secrets is accepted.
        signature_header.split.any? do |part|
          version, _, signature = part.partition(",")
          next false if version != "v1" || signature.empty?

          expected.any? { |candidate| secure_compare(signature, candidate) }
        end
      end

      # .verify_signature, then parses the body: raises WebhookSignatureError on a bad signature
      # rather than returning a boolean, for call sites that want to raise on failure. Never
      # includes the secret or the raw body in the error.
      def construct_event(secrets, headers, raw_body, tolerance_seconds: DEFAULT_TOLERANCE_SECONDS, now: nil)
        unless verify_signature(secrets, headers, raw_body, tolerance_seconds: tolerance_seconds, now: now)
          raise WebhookSignatureError, "webhook signature verification failed"
        end

        parsed = JSON.parse(raw_body)
        WebhookEvent.new(id: parsed["id"], type: parsed["type"], domain: parsed["domain"], data: parsed["data"])
      end

      # Builds a validly signed request FOR YOUR OWN TESTS: the headers a real Duva webhook
      # delivery would carry for `body`, signed with `secret` as of `timestamp` (Unix seconds;
      # defaults to now). Never used by the library itself to send anything: Duva is the only
      # real sender.
      def sign(secret, event_id, body, timestamp: nil)
        at = timestamp || Time.now.to_i
        ts = at.to_s
        signature = expected_signature(secret, event_id, ts, body)
        {
          "content-type" => "application/json",
          "webhook-id" => event_id,
          "webhook-timestamp" => ts,
          "webhook-signature" => "v1,#{signature}"
        }
      end

      private

      def header(headers, name)
        match = headers.find { |key, _| key.to_s.downcase == name }
        match && match[1]
      end

      def decode_secret(secret)
        raise WebhookSignatureError, "a Duva webhook secret starts with whsec_" unless secret.start_with?(SECRET_PREFIX)

        Base64.strict_decode64(secret.delete_prefix(SECRET_PREFIX))
      rescue ArgumentError
        raise WebhookSignatureError, "a Duva webhook secret starts with whsec_"
      end

      def expected_signature(secret, event_id, timestamp, raw_body)
        key = decode_secret(secret)
        digest = OpenSSL::HMAC.digest("SHA256", key, "#{event_id}.#{timestamp}.#{raw_body}")
        Base64.strict_encode64(digest)
      end

      def expected_signatures(secret_list, event_id, timestamp, raw_body)
        secret_list.map { |secret| expected_signature(secret, event_id, timestamp, raw_body) }
      rescue WebhookSignatureError
        nil
      end

      def secure_compare(left, right)
        OpenSSL.secure_compare(left, right)
      rescue TypeError, ArgumentError
        false # secure_compare requires equal-length strings; a mismatched length is just "false"
      end
    end
  end
end
