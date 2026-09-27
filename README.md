# Duva for Ruby

The official [Duva](https://duva.ca) client library for Ruby. Duva is a transactional email API
hosted in Canada.

```bash
gem install duva-mail
# or, in a Gemfile: gem "duva-mail"
```

Requires Ruby 3.3 or later. No runtime dependency beyond `base64` (bundled with Ruby; declared
explicitly since it left Ruby's default gems in 3.4).

## Sending a message

```ruby
require "duva"

duva = Duva::Client.new(api_key: "dv_...", domain: "example.com") # or DUVA_API_KEY / DUVA_DOMAIN

message = duva.messages.deliver(
  from: "Example <notifications@example.com>",
  to: ["client@example.org"],
  subject: "Your order",
  text: "Thank you for your order."
)
puts message.id, message.status # "queued": always asynchronous
```

Named `deliver`, not `send`: `Object#send` is a core Ruby method and shadowing it would be
confusing in a `rescue`/`method_missing`-heavy codebase.

## Reading events and pagination

```ruby
duva.events.list_all(type: "bounced").each { |event| puts event.type, event.detail["recipient"] }
```

`events.list` and `suppressions.list` return one page (`.data`, `.next_cursor`); `events.list_all`
and `suppressions.list_all` return a lazy `Enumerator` that follows `next_cursor` for you, without
ever loading every page into memory, optionally bounded with `max_items:`.

## Verifying a webhook

```ruby
begin
  event = Duva::Webhooks.construct_event(ENV.fetch("DUVA_WEBHOOK_SECRET"), request.headers, raw_body)
  puts event.type, event.data["message_id"]
rescue Duva::WebhookSignatureError
  # respond 400
end
```

`raw_body` must be the **exact bytes** Duva sent (`request.raw_post` in Rails, `request.body.read`
in Sinatra/Rack): re-encoding a parsed body changes it and invalidates the signature. Rotating
your webhook secret? Pass an array — `Duva::Webhooks.construct_event([old_secret, new_secret], ...)`
— while both are active.

## Errors

Every error Duva answers with is a `Duva::Error` subclass; rely on `.code` (the contract), never on
the exception message (its wording can change):

```ruby
begin
  duva.messages.deliver(...)
rescue Duva::ValidationError => e
  p e.fields # [{"field" => "to[0]", "message" => "..."}]
rescue Duva::QuotaExceededError => e
  puts "retry in #{e.retry_after}s"
rescue Duva::NotFoundError
  # the API key, domain or resource could not be found
end
```

Network failures and timeouts raise `Duva::ConnectionError` / `Duva::TimeoutError` instead (no
HTTP response was ever received). Reads and `messages.deliver` (idempotency-key protected) are
retried automatically on a transient failure; `suppressions.add`/`remove` and
`webhooks.create`/`delete` are not, because the outcome of a timed-out first attempt is unknown. A
`429 quota_exceeded` is never retried automatically (its `retry_after` can be hours); a
`429 rate_limited` is, as long as the wait fits within `max_retry_wait_seconds` (30s by default).

## Attachments

```ruby
attachment = Duva::Attachments.from_file("./invoice.pdf")
duva.messages.deliver(..., attachments: [attachment])
```

`Duva::Attachments.from_bytes(filename, content, content_type:, content_id:)` works from data
already in memory; `content_id:` turns the attachment into an inline image the HTML references
with `cid:`.

## Testing your own application

```ruby
transport = Duva::TestTransport.new do |_config, spec|
  Duva::TestTransport.response({ "status" => "ok" })
end
duva = Duva::Client.new(api_key: "dv_test", domain: "example.com", transport: transport)
duva.health
transport.requests.last.path # => "/health"
```

`Duva::TestTransport` records every `RequestSpec` sent and lets you script the responses: no
network call, no stubbing library required.

## Configuration

| Argument | Default | |
|---|---|---|
| `api_key:` | `DUVA_API_KEY` | Required. |
| `domain:` | `DUVA_DOMAIN` | Required: the domain this key was created for. |
| `base_url:` | `https://api.duva.ca` | |
| `timeout:` | `10` (seconds) | |
| `max_retries:` | `2` | Network failures / `5xx` on a safe-to-retry call. |
| `max_retry_wait_seconds:` | `30` | A `429 rate_limited` with a longer wait is not retried. |
| `language:` | unset | `"en"` or `"fr"`: the language of `error.message`. |
| `transport:` | a new `Duva::NetHttpTransport` (`Net::HTTP`, no gem dependency) | Inject your own (proxying, Faraday, tests). |

## Full reference

The complete API surface and the OpenAPI specification this library follows:
<https://duva.ca/en/docs> and <https://duva.ca/openapi.json>.

## Development

```bash
bundle install
bundle exec rake spec                                  # unit tests
ruby script/fetch_conformance.rb && bundle exec rake conformance
bundle exec rake rubocop
gem build duva-mail.gemspec
```

Response types are hand-written value objects (`lib/duva/models.rb`, `Data.define`): Ruby's typing
is optional (RBS/Sorbet are left to the application), so there is no separate code-generation step
for them, unlike the Node.js and Python libraries. The client itself (retries, pagination, errors,
webhooks) is checked against the shared fixtures published in
[`duva-mail/duva-conformance`](https://github.com/duva-mail/duva-conformance).

## License

MIT, see [LICENSE](./LICENSE).
