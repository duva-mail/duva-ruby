#!/usr/bin/env ruby
# frozen_string_literal: true

# Fetches the public fixtures of `duva-mail/duva-conformance` (generated and tested in the
# `duva` repository: see `docs/bibliotheques-clientes.md` section 6). Never committed here (see
# `.gitignore`): always the freshest version, never a copy that could silently drift.
#
#   ruby script/fetch_conformance.rb

require "net/http"
require "fileutils"

BASE = "https://raw.githubusercontent.com/duva-mail/duva-conformance/main"
FILES = %w[webhooks.json requests.json retries.json].freeze
OUTPUT_DIR = File.expand_path("../conformance", __dir__)

FileUtils.mkdir_p(OUTPUT_DIR)
FILES.each do |name|
  response = Net::HTTP.get_response(URI("#{BASE}/#{name}"))
  raise "fetching #{name}: HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

  File.write(File.join(OUTPUT_DIR, name), response.body)
  puts "conformance/#{name} fetched"
end
