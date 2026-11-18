# frozen_string_literal: true

require 'simplecov'
SimpleCov.start 'rails' do
  skip %w[/spec/ /config/ /db/ /bin/]
  minimum_coverage 95
  coverage(:line) { minimum 70, per: :file }
end

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
  config.expect_with(:rspec) { |expectations| expectations.syntax = :expect }
end
