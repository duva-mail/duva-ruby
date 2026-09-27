# frozen_string_literal: true

module Duva
  # Base of every error raised for a request Duva actually answered (as opposed to a network
  # failure: see ConnectionError and TimeoutError). Mapped from `error.code` (the contract),
  # never from the HTTP status alone or the wording of `error.message` (which can change between
  # languages and over time). See `docs/bibliotheques-clientes.md` section 3.6 in the `duva`
  # repository for the source table.
  class Error < StandardError
    # The HTTP status Duva answered with.
    attr_reader :status
    # `error.code`: the contract. Rely on this, never on the exception message.
    attr_reader :code
    # `error.fields`, when the error is a validation error (`code == "invalid_request"`).
    attr_reader :fields
    # The raw response body, bounded to 4 KB: never includes your API key.
    attr_reader :raw_body

    def initialize(status:, code:, message:, raw_body:, fields: nil)
      super(message)
      @status = status
      @code = code
      @fields = fields
      @raw_body = raw_body.to_s[0, 4096]
    end

    # Never leak the raw body (which could, in principle, carry a stray fragment of a request)
    # through the default `#inspect` a debugger or a crash report would print.
    def inspect
      "#<#{self.class}: status=#{status} code=#{code.inspect}>"
    end
  end

  class AuthenticationError < Error; end
  class NotFoundError < Error; end

  # `domain_not_verified` or `sending_not_allowed`; `code` distinguishes the two.
  class PermissionError < Error; end

  # `idempotency_conflict` or `limit_reached`; `code` distinguishes the two.
  class ConflictError < Error; end

  class PayloadTooLargeError < Error; end

  class ValidationError < Error
    def initialize(status:, code:, message:, raw_body:, fields: nil)
      super(status: status, code: code, message: message, raw_body: raw_body, fields: fields || [])
    end
  end

  # A `429` on YOUR ACCOUNT quota (daily or monthly). `retry_after` can be hours: never retried
  # automatically, by design (see `docs/bibliotheques-clientes.md` section 3.5).
  class QuotaExceededError < Error
    attr_reader :retry_after

    def initialize(status:, code:, message:, raw_body:, fields:, retry_after:)
      super(status: status, code: code, message: message, raw_body: raw_body, fields: fields)
      @retry_after = retry_after
    end
  end

  # A `429` from the per-key rate limit (unrelated to your sending quota). Retried automatically
  # when `retry_after` fits within `max_retry_wait_seconds`.
  class RateLimitError < Error
    attr_reader :retry_after

    def initialize(status:, code:, message:, raw_body:, fields:, retry_after:)
      super(status: status, code: code, message: message, raw_body: raw_body, fields: fields)
      @retry_after = retry_after
    end
  end

  # A `5xx`, or a response whose body was not the documented error envelope.
  class ServerError < Error; end

  # No response was received at all (DNS, TLS, connection refused, connection reset...). The
  # original exception is kept as `#cause` (Ruby's own chaining, via `raise ... from:`-less
  # `raise` inside a `rescue` block).
  class ConnectionError < StandardError; end

  # The request exceeded `timeout` before any response arrived.
  class TimeoutError < StandardError; end

  # A webhook signature failed to verify: never carries the secret or the raw body.
  class WebhookSignatureError < StandardError; end

  # @api private
  CODES = {
    "unauthorized" => AuthenticationError,
    "not_found" => NotFoundError,
    "domain_not_verified" => PermissionError,
    "sending_not_allowed" => PermissionError,
    "idempotency_conflict" => ConflictError,
    "limit_reached" => ConflictError,
    "payload_too_large" => PayloadTooLargeError,
    "invalid_request" => ValidationError,
    "internal_error" => ServerError,
    "method_not_allowed" => ServerError,
    "http_error" => ServerError
  }.freeze
  private_constant :CODES

  # Builds the right Error subclass from a parsed response body, or a generic ServerError when
  # the body does not match the documented envelope (a proxy error page, for instance): never
  # raises itself.
  #
  # @api private
  def self.error_from_response(status, parsed_body, raw_body, retry_after_header)
    code, message, fields = as_error_body(parsed_body)
    retry_after = retry_after_header ? retry_after_header.to_i : 0
    case code
    when "quota_exceeded"
      QuotaExceededError.new(status: status, code: code, message: message, raw_body: raw_body,
                             fields: fields, retry_after: retry_after)
    when "rate_limited"
      RateLimitError.new(status: status, code: code, message: message, raw_body: raw_body,
                         fields: fields, retry_after: retry_after)
    else
      klass = CODES.fetch(code, ServerError)
      klass.new(status: status, code: code, message: message, raw_body: raw_body, fields: fields)
    end
  end

  # @api private
  def self.as_error_body(value)
    error = value.is_a?(Hash) && value["error"].is_a?(Hash) ? value["error"] : nil
    return ["http_error", "Duva answered with an unexpected body.", nil] unless error.is_a?(Hash) && error["code"].is_a?(String)

    [error["code"], error["message"] || "", error["fields"]]
  end
  private_class_method :as_error_body
end
