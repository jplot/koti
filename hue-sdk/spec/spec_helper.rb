# frozen_string_literal: true

require 'simplecov'
SimpleCov.start do
  skip '/spec/'
  minimum_coverage 95
  coverage(:line) { minimum 70, per: :file }
end

require 'hue/sdk'

Dir[File.join(__dir__, 'support/**/*.rb')].each { require it }

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |expectations| expectations.syntax = :expect }
  config.filter_run_excluding :live unless ENV['HUE_LIVE'] == '1'
end
