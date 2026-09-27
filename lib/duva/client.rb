# frozen_string_literal: true

require "securerandom"

module Duva
  # Decides whether a failed request may be retried, exactly per
  # `docs/bibliotheques-clientes.md` section 3.5 in the `duva` repository.
  #
  # @api private
  module RetryPolicy
    module_function

    # `nil` = do not retry (re-raise); a number = wait this many seconds, then retry.
    def delay_for(error, spec, attempt, config)
      if error.is_a?(RateLimitError)
        return error.retry_after > config.max_retry_wait_seconds ? nil : error.retry_after.to_f
      end
      # A QuotaExceededError (has retry_after too) is never retried automatically; neither is
      # any other DuvaError that isn't a ServerError (4xx: the outcome is already known).
      return nil if error.is_a?(Error) && !error.is_a?(ServerError)

      transient = error.is_a?(ConnectionError) || error.is_a?(TimeoutError) || error.is_a?(ServerError)
      return nil unless transient && spec.safe_retry && attempt < config.max_retries

      backoff(attempt)
    end

    # Exponential backoff with jitter, capped: never a fixed delay, never unbounded.
    def backoff(attempt)
      base = [0.5 * (2.0**attempt), 8.0].min
      (base / 2) + (rand * (base / 2))
    end
  end
  private_constant :RetryPolicy

  # What `messages.deliver` returns: the accepted message plus the idempotency outcome.
  SendMessageResult = Data.define(:id, :status, :replayed, :location)

  # A synchronous Duva client, bound to one domain and its API key.
  #
  #   duva = Duva::Client.new(api_key: "dv_...", domain: "example.com")
  #   message = duva.messages.deliver(
  #     from: "Example <notifications@example.com>",
  #     to: ["client@example.org"],
  #     subject: "Your order",
  #     text: "Thank you for your order.",
  #   )
  class Client
    # @api private
    attr_reader :config
    attr_reader :messages, :events, :suppressions, :webhooks, :stats

    def initialize(api_key: nil, domain: nil, base_url: Duva::DEFAULT_BASE_URL, timeout: 10, max_retries: 2,
                   max_retry_wait_seconds: 30, language: nil, user_agent: nil, transport: nil)
      @config = Config.resolve(api_key: api_key, domain: domain, base_url: base_url, timeout: timeout,
                               max_retries: max_retries, max_retry_wait_seconds: max_retry_wait_seconds,
                               language: language, user_agent: user_agent)
      @transport = transport || NetHttpTransport.new
      @messages = MessagesResource.new(self)
      @events = EventsResource.new(self)
      @suppressions = SuppressionsResource.new(self)
      @webhooks = WebhooksResource.new(self)
      @stats = StatsResource.new(self)
    end

    # `GET /health`, without authentication: `{"status" => "ok"}` when the service works. Raises
    # ServerError on a `503` (its database is unreachable).
    def health
      request(RequestSpec.new(method: "GET", path: "/health", safe_retry: true)).data
    end

    # @api private
    def request(spec)
      attempt = 0
      loop do
        return @transport.call(@config, spec)
      rescue Error, ConnectionError, TimeoutError => e
        delay = RetryPolicy.delay_for(e, spec, attempt, @config)
        raise e if delay.nil?

        attempt += 1
        sleep(delay)
      end
    end
  end

  # @api private
  class MessagesResource
    def initialize(client)
      @client = client
    end

    # Accepts a message for delivery. Always asynchronous: `queued` never confirms a delivery,
    # only that the message was validated. Read the outcome with `messages.get`, `events.list`,
    # or a webhook. Named `deliver`, not `send`: `Object#send` is a core Ruby method.
    #
    # `idempotency_key:`: unique per domain. A UUID is generated when omitted (see
    # `docs/bibliotheques-clientes.md` section 3.3): a network-level retry of the SAME call can
    # then never create a duplicate message, but two separate calls each get their own random
    # key, so they are NOT deduplicated against each other; pass your own stable key for that
    # (e.g. an order id).
    def deliver(from:, to:, subject:, idempotency_key: nil, **fields)
      body = message_body(from: from, to: to, subject: subject, **fields)
      key = idempotency_key || SecureRandom.uuid
      result = @client.request(RequestSpec.new(method: "POST", path: "#{@client.config.domain_path}/messages",
                                               body: body, idempotency_key: key, safe_retry: true))
      accepted = MessageAccepted.from_json_hash(result.data)
      SendMessageResult.new(id: accepted.id, status: accepted.status,
                            replayed: result.headers["idempotent-replayed"] == "true",
                            location: result.headers["location"])
    end

    # The message's status and each recipient's status.
    def get(id)
      result = @client.request(RequestSpec.new(method: "GET", path: "#{@client.config.domain_path}/messages/#{id}",
                                               safe_retry: true))
      Message.from_json_hash(result.data)
    end

    private

    def message_body(from:, to:, subject:, html: nil, text: nil, tags: nil, tracking: nil, reply_to: nil,
                     headers: nil, metadata: nil, attachments: nil)
      Attachments.assert_limits(attachments) if attachments && !attachments.empty?
      body = { "from" => from, "to" => to, "subject" => subject }
      body["html"] = html unless html.nil?
      body["text"] = text unless text.nil?
      body["tags"] = tags unless tags.nil?
      unless tracking.nil?
        body["tracking"] =
          { "opens" => tracking.fetch(:opens, false), "clicks" => tracking.fetch(:clicks, false) }
      end
      body["reply_to"] = reply_to unless reply_to.nil?
      body["headers"] = headers unless headers.nil?
      body["metadata"] = metadata unless metadata.nil?
      body["attachments"] = attachments.map(&:to_h) unless attachments.nil?
      body
    end
  end

  # @api private
  class EventsResource
    def initialize(client)
      @client = client
    end

    # One page of delivery events, most recent first.
    def list(message_id: nil, type: nil, recipient: nil, since: nil, limit: nil, cursor: nil)
      query = { "message_id" => message_id, "type" => type, "recipient" => recipient,
                "since" => since&.iso8601, "limit" => limit, "cursor" => cursor }
      result = @client.request(RequestSpec.new(method: "GET", path: "#{@client.config.domain_path}/events", query: query,
                                               safe_retry: true))
      EventPage.from_json_hash(result.data)
    end

    # Every delivery event, most recent first, following `next_cursor` automatically. Returns a
    # lazy Enumerator (nothing is fetched until you iterate).
    def list_all(message_id: nil, type: nil, recipient: nil, since: nil, max_items: nil)
      Pagination.paginate(max_items: max_items) do |cursor|
        list(message_id: message_id, type: type, recipient: recipient, since: since, cursor: cursor)
      end
    end
  end

  # @api private
  class SuppressionsResource
    def initialize(client)
      @client = client
    end

    # One page of suppressed addresses, most recent first.
    def list(reason: nil, limit: nil, cursor: nil)
      query = { "reason" => reason, "limit" => limit, "cursor" => cursor }
      result = @client.request(RequestSpec.new(method: "GET", path: "#{@client.config.domain_path}/suppressions", query: query,
                                               safe_retry: true))
      SuppressionPage.from_json_hash(result.data)
    end

    # Every suppressed address, most recent first, following `next_cursor` automatically.
    def list_all(reason: nil, max_items: nil)
      Pagination.paginate(max_items: max_items) { |cursor| list(reason: reason, cursor: cursor) }
    end

    # Adds an address by hand (reason `manual`): it receives nothing more from this domain.
    # Naturally idempotent: adding an already-suppressed address changes nothing.
    def add(email)
      result = @client.request(RequestSpec.new(method: "POST", path: "#{@client.config.domain_path}/suppressions",
                                               body: { "email" => email }, safe_retry: false))
      Suppression.from_json_hash(result.data)
    end

    # Removes an address from the list: it may receive mail again. Raises NotFoundError if it
    # was not on the list.
    def remove(email)
      path = "#{@client.config.domain_path}/suppressions/#{Config.percent_encode(email)}"
      @client.request(RequestSpec.new(method: "DELETE", path: path, safe_retry: false))
      nil
    end
  end

  # @api private
  class WebhooksResource
    def initialize(client)
      @client = client
    end

    # Registers an endpoint. The response carries the signing `secret` (`whsec_...`): shown
    # ONCE, store it to verify signatures. Each call creates a DISTINCT endpoint, never retried
    # automatically.
    def create(url, events: nil)
      result = @client.request(RequestSpec.new(method: "POST", path: "#{@client.config.domain_path}/webhooks",
                                               body: { "url" => url, "events" => events || [] }, safe_retry: false))
      Webhook.from_json_hash(result.data)
    end

    def list
      result = @client.request(RequestSpec.new(method: "GET", path: "#{@client.config.domain_path}/webhooks", safe_retry: true))
      WebhookList.from_json_hash(result.data).data
    end

    def get(id)
      result = @client.request(RequestSpec.new(method: "GET", path: "#{@client.config.domain_path}/webhooks/#{id}",
                                               safe_retry: true))
      Webhook.from_json_hash(result.data)
    end

    def delete(id)
      @client.request(RequestSpec.new(method: "DELETE", path: "#{@client.config.domain_path}/webhooks/#{id}", safe_retry: false))
      nil
    end

    # The latest deliveries of this endpoint (`limit`: 1 to 100, 50 by default).
    def deliveries(id, limit: nil)
      path = "#{@client.config.domain_path}/webhooks/#{id}/deliveries"
      result = @client.request(RequestSpec.new(method: "GET", path: path, query: { "limit" => limit }, safe_retry: true))
      WebhookDeliveryList.from_json_hash(result.data).data
    end
  end

  # @api private
  class StatsResource
    def initialize(client)
      @client = client
    end

    # Counters of the domain by period (UTC). Defaults to the last 30 days (or 24 hours, by
    # hour). At most 366 days, or 7 days by hour.
    def get(granularity: nil, since: nil, until_: nil)
      query = { "granularity" => granularity, "since" => since&.iso8601, "until" => until_&.iso8601 }
      result = @client.request(RequestSpec.new(method: "GET", path: "#{@client.config.domain_path}/stats", query: query,
                                               safe_retry: true))
      Stats.from_json_hash(result.data)
    end
  end
end
