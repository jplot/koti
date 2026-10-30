# frozen_string_literal: true

require 'simplecov'
SimpleCov.start do
  skip '/spec/'
  skip %r{\Alib/ajax/sdk/cloud/messages}
  # A live run exercises only the paths a real hub can answer read-only: it would fail the thresholds.
  unless ENV['AJAX_LIVE'] == '1'
    minimum_coverage 95
    coverage(:line) { minimum 70, per: :file }
  end
end

require 'ajax/sdk'

Dir[File.join(__dir__, 'support/**/*.rb')].each { require it }

require 'timeout'

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
  config.expect_with(:rspec) { |expectations| expectations.syntax = :expect }
  config.filter_run_excluding :live unless ENV['AJAX_LIVE'] == '1'
  config.around { |example| Timeout.timeout(20) { example.run } }
end
