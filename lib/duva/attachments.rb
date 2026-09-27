# frozen_string_literal: true

require "base64"

module Duva
  # Attachment helpers. The server remains the authority on the limits below (they can change):
  # these are a courtesy, so a mistake fails locally instead of after an upload.
  Attachment = Data.define(:filename, :content, :content_type, :content_id) do
    def to_h
      { "filename" => filename, "content" => content, "content_type" => content_type, "content_id" => content_id }
    end
  end

  module Attachments
    # Mirrors `services/messages.py` in the `duva` repository at the time of writing: 10
    # attachments, 5 MB decoded in total, these extensions refused. Re-check against
    # `docs/api.md` if this drifts.
    MAX_ATTACHMENTS = 10
    MAX_TOTAL_BYTES = 5 * 1024 * 1024
    FORBIDDEN_EXTENSIONS = %w[.exe .bat .cmd .com .js .vbs .vbe .scr .msi .msp .ps1 .jar].freeze

    class << self
      # From raw bytes already in memory.
      def from_bytes(filename, content, content_type: nil, content_id: nil)
        assert_allowed_filename(filename)
        Attachment.new(filename: filename, content: Base64.strict_encode64(content),
                       content_type: content_type, content_id: content_id)
      end

      # Reads a file from disk.
      def from_file(path, content_type: nil, content_id: nil, filename: nil)
        from_bytes(filename || File.basename(path), File.binread(path), content_type: content_type, content_id: content_id)
      end

      # Local, courtesy-only checks: at most MAX_ATTACHMENTS attachments, at most
      # MAX_TOTAL_BYTES decoded in total. Raises ArgumentError when exceeded; the server
      # re-checks regardless.
      def assert_limits(attachments)
        raise ArgumentError, "Duva: at most #{MAX_ATTACHMENTS} attachments per message" if attachments.size > MAX_ATTACHMENTS

        total_bytes = attachments.sum { |a| decoded_length(a.content) }
        return unless total_bytes > MAX_TOTAL_BYTES

        raise ArgumentError, "Duva: attachments are #{total_bytes} bytes decoded, over the #{MAX_TOTAL_BYTES} limit"
      end

      private

      def assert_allowed_filename(filename)
        if filename.include?("/") || filename.include?("\\")
          raise ArgumentError,
                "Duva: attachment filename must not contain a path: #{filename}"
        end

        ext = File.extname(filename).downcase
        raise ArgumentError, "Duva: executable attachments are refused: #{filename}" if FORBIDDEN_EXTENSIONS.include?(ext)
      end

      def decoded_length(base64)
        padding = if base64.end_with?("==")
                    2
                  elsif base64.end_with?("=")
                    1
                  else
                    0
                  end
        (base64.length * 3 / 4) - padding
      end
    end
  end
end
