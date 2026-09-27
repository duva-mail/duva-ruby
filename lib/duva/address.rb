# frozen_string_literal: true

module Duva
  # Small formatting helpers matched to the API's own parsing rules (`docs/api.md`).
  module Address
    NEEDS_QUOTING = /[",]/
    private_constant :NEEDS_QUOTING

    class << self
      # `"Name <address>"` (with `Name` quoted if it contains a `"` or `,`), or just `address`
      # without a name.
      def format(email, name = nil)
        return email if name.nil? || name.empty?

        escaped = name.gsub('"', '\\"')
        quoted = NEEDS_QUOTING.match?(name) ? "\"#{escaped}\"" : name
        "#{quoted} <#{email}>"
      end

      # Builds `List-Unsubscribe` (and `List-Unsubscribe-Post` for one-click) exactly as the API
      # validates them: at most 3 links, `https://` or `mailto:` only. Raises ArgumentError when
      # neither `https_url:` nor `mailto:` is given.
      #
      # `one_click:` adds `List-Unsubscribe-Post` (RFC 8058). Defaults to `true` when
      # `https_url:` is given, `false` otherwise.
      def unsubscribe_headers(https_url: nil, mailto: nil, one_click: nil)
        raise ArgumentError, "Duva: unsubscribe_headers needs https_url and/or mailto" if https_url.nil? && mailto.nil?
        if https_url && !https_url.start_with?("https://")
          raise ArgumentError,
                "Duva: unsubscribe_headers.https_url must be an https:// link"
        end

        resolved_one_click = one_click.nil? ? !https_url.nil? : one_click

        links = [https_url, mailto && "mailto:#{mailto}"].compact.map { |link| "<#{link}>" }
        headers = { "List-Unsubscribe" => links.join(", ") }
        if resolved_one_click
          raise ArgumentError, "Duva: one-click unsubscribe (List-Unsubscribe-Post) needs https_url" unless https_url

          headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"
        end
        headers
      end
    end
  end
end
