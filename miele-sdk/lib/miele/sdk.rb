# frozen_string_literal: true

require_relative 'sdk/version'
require_relative 'sdk/errors'
require_relative 'sdk/configuration'

# Namespace of the koti SDKs for the Miele ecosystem.
module Miele
  # Unofficial Ruby SDK for Miele@home appliances, talking to them on the
  # local network with the household key.
  #
  # @example Configure the household key
  #   Miele::Sdk.configure do |config|
  #     config.group_id = ENV.fetch('MIELE_GROUP_ID')
  #     config.group_key = ENV.fetch('MIELE_GROUP_KEY')
  #   end
  module Sdk
    extend Configuration
  end
end
