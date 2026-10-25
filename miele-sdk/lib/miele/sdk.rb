# frozen_string_literal: true

require_relative 'sdk/version'
require_relative 'sdk/errors'
require_relative 'sdk/configuration'
require_relative 'sdk/crypto'
require_relative 'sdk/connection'
require_relative 'sdk/discovery'
require_relative 'sdk/catalog/device_types'
require_relative 'sdk/catalog/status'
require_relative 'sdk/catalog/program_types'
require_relative 'sdk/catalog/program_phases'
require_relative 'sdk/state'
require_relative 'sdk/dop2'
require_relative 'sdk/appliance'

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

    # Finds Miele@home appliances on the local network.
    #
    # @param timeout [Numeric] seconds to listen (default: 4, time for queries at 0, 1 and 3 seconds)
    # @param address [String] where to send the mDNS query (default: the mDNS multicast group)
    # @param port [Integer] destination port of the query (default: 5353)
    # @return [Array<Discovery::Appliance>]
    # @api public
    def self.discover(timeout: 4, address: '224.0.0.251', port: 5353) = Discovery.discover(timeout:, address:, port:)

    # @param host [String] address or +.local+ name of the appliance
    # @return [Appliance]
    # @api public
    def self.appliance(host) = Appliance.new(host)
  end
end
