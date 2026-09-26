Gem::Specification.new do |spec|
  spec.name = "duva"
  spec.version = "0.0.1"
  spec.summary = "Official Duva client library (name reserved, not released yet)"
  spec.description = "Official client library for Duva, a transactional email API hosted in Canada. This name is reserved: the library is not released yet."
  spec.authors = ["9573-4562 Québec inc."]
  spec.license = "MIT"
  spec.homepage = "https://duva.ca"
  spec.metadata = {
    "source_code_uri" => "https://github.com/duva-mail/duva-ruby",
    "documentation_uri" => "https://duva.ca/en/docs",
    "rubygems_mfa_required" => "true"
  }
  spec.required_ruby_version = ">= 3.3"
  spec.files = ["lib/duva.rb", "README.md", "LICENSE"]
  spec.require_paths = ["lib"]
end
