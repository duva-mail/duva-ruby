# frozen_string_literal: true

require "rspec/core/rake_task"
require "rubocop/rake_task"

RSpec::Core::RakeTask.new(:spec) do |t|
  t.exclude_pattern = "spec/conformance/**/*_spec.rb"
end

RSpec::Core::RakeTask.new(:conformance) do |t|
  t.pattern = "spec/conformance/**/*_spec.rb"
end

RuboCop::RakeTask.new

task default: %i[spec rubocop]
