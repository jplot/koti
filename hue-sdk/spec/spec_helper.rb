# frozen_string_literal: true

require 'simplecov'
SimpleCov.start do
  skip '/spec/'
  # A live run (5 examples against a real bridge) covers 92 % on its own and would fail the thresholds.
  unless ENV['HUE_LIVE'] == '1'
    minimum_coverage 95
    coverage(:line) { minimum 70, per: :file }
  end
end

require 'hue/sdk'

Dir[File.join(__dir__, 'support/**/*.rb')].each { require it }

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
  config.expect_with(:rspec) { |expectations| expectations.syntax = :expect }
  config.filter_run_excluding :live unless ENV['HUE_LIVE'] == '1'
end
