# frozen_string_literal: true

module Duva
  # A scriptable fake Transport (`docs/bibliotheques-clientes.md` section 3.10: "a fake
  # transport and a response builder, so you can test YOUR OWN application without a network
  # call"). Inject it via `Client.new(transport: ...)`.
  #
  #   transport = Duva::TestTransport.new { |_config, spec| Duva::TestTransport.response({"status" => "ok"}) }
  #   duva = Duva::Client.new(api_key: "dv_test", domain: "example.com", transport: transport)
  #   duva.health
  #   transport.requests.last.path # => "/health"
  class TestTransport
    # Every RequestSpec actually sent, in order: inspect it to assert what your code sent.
    attr_reader :requests

    # `handler` receives `(config, spec)` for each call and must return a RawResponse (see
    # .response) or raise a Duva::Error subclass, Duva::ConnectionError or Duva::TimeoutError.
    def initialize(&handler)
      @handler = handler
      @requests = []
    end

    # @api private
    def call(config, spec)
      @requests << spec
      @handler.call(config, spec)
    end

    # Builds a RawResponse from a plain Hash (or nil, for a 204), as your handler returns it.
    def self.response(data = nil, headers: {})
      RawResponse.new(data: data, headers: headers.transform_keys { |k| k.to_s.downcase })
    end
  end
end
