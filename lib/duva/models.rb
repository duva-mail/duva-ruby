# frozen_string_literal: true

require "time"

module Duva
  # Hand-written response value objects (Ruby's typing is optional per
  # `docs/bibliotheques-clientes.md` section 4 -- RBS/Sorbet are left to the application, unlike
  # the generated models of the Node.js and Python libraries). Each `.from_json_hash` factory
  # reads only the fields it knows and ignores the rest, and never restricts a string enum-like
  # field (`status`, `type`, `reason`...) to a fixed set: a value the server adds later still
  # comes through as plain text rather than raising (section 3.7, "tolerance").
  #
  # @api private
  module Models
    def self.time(value)
      value && Time.iso8601(value)
    end
  end
  private_constant :Models

  Tracking = Data.define(:opens, :clicks) do
    def self.from_json_hash(h)
      new(opens: h["opens"] || false, clicks: h["clicks"] || false)
    end
  end

  Recipient = Data.define(:email, :status, :updated_at) do
    def self.from_json_hash(h)
      new(email: h["email"], status: h["status"], updated_at: Models.time(h["updated_at"]))
    end
  end

  Message = Data.define(:id, :status, :from, :subject, :tags, :metadata, :tracking, :created_at, :recipients) do
    def self.from_json_hash(h)
      new(
        id: h["id"], status: h["status"], from: h["from"], subject: h["subject"],
        tags: h["tags"] || [], metadata: h["metadata"] || {},
        tracking: Tracking.from_json_hash(h["tracking"] || {}),
        created_at: Models.time(h["created_at"]),
        recipients: (h["recipients"] || []).map { |r| Recipient.from_json_hash(r) }
      )
    end
  end

  MessageAccepted = Data.define(:id, :status) do
    def self.from_json_hash(h)
      new(id: h["id"], status: h["status"])
    end
  end

  Event = Data.define(:id, :type, :message_id, :recipient, :occurred_at, :detail, :metadata) do
    def self.from_json_hash(h)
      new(
        id: h["id"], type: h["type"], message_id: h["message_id"], recipient: h["recipient"],
        occurred_at: Models.time(h["occurred_at"]), detail: h["detail"] || {}, metadata: h["metadata"] || {}
      )
    end
  end

  EventPage = Data.define(:data, :next_cursor) do
    def self.from_json_hash(h)
      new(data: (h["data"] || []).map { |e| Event.from_json_hash(e) }, next_cursor: h["next_cursor"])
    end
  end

  Suppression = Data.define(:email, :reason, :message_id, :created_at) do
    def self.from_json_hash(h)
      new(email: h["email"], reason: h["reason"], message_id: h["message_id"], created_at: Models.time(h["created_at"]))
    end
  end

  SuppressionPage = Data.define(:data, :next_cursor) do
    def self.from_json_hash(h)
      new(data: (h["data"] || []).map { |s| Suppression.from_json_hash(s) }, next_cursor: h["next_cursor"])
    end
  end

  Webhook = Data.define(:id, :url, :events, :status, :disabled_reason, :created_at, :secret) do
    def self.from_json_hash(h)
      new(
        id: h["id"], url: h["url"], events: h["events"] || [], status: h["status"],
        disabled_reason: h["disabled_reason"], created_at: Models.time(h["created_at"]), secret: h["secret"]
      )
    end
  end

  WebhookList = Data.define(:data) do
    def self.from_json_hash(h)
      new(data: (h["data"] || []).map { |w| Webhook.from_json_hash(w) })
    end
  end

  WebhookDelivery = Data.define(:id, :event_id, :status, :attempts, :last_status_code, :last_error, :created_at, :delivered_at) do
    def self.from_json_hash(h)
      new(
        id: h["id"], event_id: h["event_id"], status: h["status"], attempts: h["attempts"],
        last_status_code: h["last_status_code"], last_error: h["last_error"],
        created_at: Models.time(h["created_at"]), delivered_at: Models.time(h["delivered_at"])
      )
    end
  end

  WebhookDeliveryList = Data.define(:data) do
    def self.from_json_hash(h)
      new(data: (h["data"] || []).map { |d| WebhookDelivery.from_json_hash(d) })
    end
  end

  StatsPeriod = Data.define(:period, :accepted, :suppressed, :delivered, :bounced, :deferred, :expired, :complained, :opened,
                            :clicked) do
    def self.from_json_hash(h)
      new(
        period: Models.time(h["period"]), accepted: h["accepted"], suppressed: h["suppressed"],
        delivered: h["delivered"], bounced: h["bounced"], deferred: h["deferred"], expired: h["expired"],
        complained: h["complained"], opened: h["opened"], clicked: h["clicked"]
      )
    end
  end

  Stats = Data.define(:granularity, :since, :until, :data, :totals) do
    def self.from_json_hash(h)
      new(
        granularity: h["granularity"], since: Models.time(h["since"]), until: Models.time(h["until"]),
        data: (h["data"] || []).map { |p| StatsPeriod.from_json_hash(p) }, totals: h["totals"] || {}
      )
    end
  end
end
