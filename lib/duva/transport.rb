# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Duva
  DEFAULT_BASE_URL = "https://api.duva.ca"

  # Resolved, validated client configuration.
  Config = Data.define(:api_key, :domain, :base_url, :timeout, :max_retries, :max_retry_wait_seconds,
                       :language, :user_agent) do
    class << self
      def resolve(api_key: nil, domain: nil, base_url: DEFAULT_BASE_URL, timeout: 10, max_retries: 2,
                  max_retry_wait_seconds: 30, language: nil, user_agent: nil)
        resolved_key = api_key || ENV.fetch("DUVA_API_KEY", nil)
        resolved_domain = domain || ENV.fetch("DUVA_DOMAIN", nil)
        raise ArgumentError, "Duva: an API key is required (api_key: or DUVA_API_KEY)" unless resolved_key
        raise ArgumentError, "Duva: a domain is required (domain: or DUVA_DOMAIN)" unless resolved_domain

        clean_base_url = base_url.chomp("/")
        unless clean_base_url.start_with?("https://") || clean_base_url.include?("localhost")
          raise ArgumentError, "Duva: base_url must be https:// (http://localhost is allowed for tests)"
        end

        new(api_key: resolved_key, domain: resolved_domain, base_url: clean_base_url, timeout: timeout,
            max_retries: max_retries, max_retry_wait_seconds: max_retry_wait_seconds, language: language,
            user_agent: user_agent)
      end

      # RFC 3986 percent-encoding with no "safe" characters (mirrors Python's
      # `urllib.parse.quote(s, safe="")`): every octet outside unreserved (`A-Za-z0-9-_.~`) is
      # escaped, including `/`.
      def percent_encode(str)
        str.b.gsub(/[^A-Za-z0-9\-_.~]/) { |char| format("%%%02X", char.ord) }
      end
    end

    # The path prefix for this client's domain (`/v1/<domain>`).
    def domain_path
      "/v1/#{self.class.percent_encode(domain)}"
    end

    def user_agent_header
      extra = user_agent ? " #{user_agent}" : ""
      "duva-ruby/#{Duva::VERSION} Ruby/#{RUBY_VERSION}#{extra}"
    end
  end

  # One HTTP call to make: built by Client, executed by a Transport.
  RequestSpec = Data.define(:method, :path, :query, :body, :idempotency_key, :safe_retry) do
    def initialize(method:, path:, query: nil, body: nil, idempotency_key: nil, safe_retry: false)
      super
    end
  end

  # A parsed response: `data` is the parsed JSON body (or nil for a 204 or an empty body),
  # `headers` a Hash with lower-cased keys.
  RawResponse = Data.define(:data, :headers)

  # Builds the wire-level shape of a request (method, URI, headers, body) from a Config and a
  # RequestSpec: a PURE function, with no I/O, so it can be checked directly (see
  # `spec/conformance/requests_spec.rb`) without a network call or a fake transport.
  #
  # @api private
  module HttpMessage
    def self.build(config, spec)
      uri = URI.parse(config.base_url + spec.path)
      uri.query = URI.encode_www_form(spec.query.compact) if spec.query && !spec.query.compact.empty?
      headers = {
        "authorization" => "Bearer #{config.api_key}",
        "user-agent" => config.user_agent_header
      }
      headers["accept-language"] = config.language if config.language
      headers["idempotency-key"] = spec.idempotency_key if spec.idempotency_key
      body = nil
      if spec.body
        headers["content-type"] = "application/json"
        body = JSON.generate(spec.body)
      end
      { method: spec.method, uri: uri, headers: headers, body: body }
    end
  end

  # Default transport: plain `Net::HTTP` (no gem dependency). Any object responding to
  # `#call(config, spec) -> RawResponse` (raising ConnectionError/TimeoutError/a Duva::Error
  # subclass as appropriate) can be injected instead -- for your own tests (see TestTransport) or
  # to plug in Faraday or another HTTP client.
  class NetHttpTransport
    def call(config, spec)
      built = HttpMessage.build(config, spec)
      request = build_net_http_request(built)
      response = perform(built[:uri], request, config.timeout)
      parse(response)
    rescue Net::OpenTimeout, Net::ReadTimeout
      raise Duva::TimeoutError, "Duva: request timed out"
    rescue SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET, OpenSSL::SSL::SSLError, IOError => e
      raise Duva::ConnectionError, "Duva: the request could not be sent: #{e.message}"
    end

    private

    def build_net_http_request(built)
      request_class = { "GET" => Net::HTTP::Get, "POST" => Net::HTTP::Post, "DELETE" => Net::HTTP::Delete }.fetch(built[:method])
      request = request_class.new(built[:uri])
      built[:headers].each { |name, value| request[name] = value }
      request.body = built[:body] if built[:body]
      request
    end

    def perform(uri, request, timeout)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: timeout, read_timeout: timeout) do |http|
        http.request(request)
      end
    end

    def parse(response)
      headers = {}
      response.each_header { |name, value| headers[name] = value }
      body = response.body
      data = body && !body.empty? ? JSON.parse(body) : nil
      code = response.code.to_i
      return RawResponse.new(data: data, headers: headers) if code < 300

      raise Duva.error_from_response(code, data, body.to_s, headers["retry-after"])
    end
  end
end
