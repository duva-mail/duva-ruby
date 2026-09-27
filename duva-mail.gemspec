# frozen_string_literal: true

require_relative "lib/duva"

Gem::Specification.new do |spec|
  spec.name = "duva-mail"
  spec.version = Duva::VERSION
  spec.summary = "Official Duva client library (transactional email API hosted in Canada)."
  spec.description = "Official client library for Duva, a transactional email API hosted in Canada: " \
                     "sending, delivery events, suppressions, webhooks and statistics."
  spec.authors = ["9573-4562 Québec inc."]
  spec.license = "MIT"
  spec.homepage = "https://duva.ca"
  spec.metadata = {
    "source_code_uri" => "https://github.com/duva-mail/duva-ruby",
    "documentation_uri" => "https://duva.ca/en/docs",
    "changelog_uri" => "https://duva.ca/en/docs#changelog",
    "rubygems_mfa_required" => "true"
  }
  spec.required_ruby_version = ">= 3.3"
  spec.files = Dir.glob("lib/**/*.rb") + ["README.md", "LICENSE", "duva-mail.gemspec"]
  spec.require_paths = ["lib"]
  # `base64` left Ruby's default gems in 3.4 (a bare `require` then warns, and would eventually
  # break): declared explicitly so it installs regardless of the running Ruby's bundled set.
  # Everything else used (json, net/http, openssl, securerandom, time, uri) remains a Ruby
  # default gem; no other dependency, matching `docs/bibliotheques-clientes.md` section 4.
  spec.add_dependency "base64", "~> 0.2"
end
