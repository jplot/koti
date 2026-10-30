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
require_relative 'sdk/catalog/programs'
require_relative 'sdk/schema'
require_relative 'sdk/remote_control'
require_relative 'sdk/state'
require_relative 'sdk/dop2'
require_relative 'sdk/dop1'
require_relative 'sdk/events/event'
require_relative 'sdk/events/advertiser'
require_relative 'sdk/events/identity'
require_relative 'sdk/events/request'
require_relative 'sdk/events/enrollment'
require_relative 'sdk/events/listener'
require_relative 'sdk/events/server'
require_relative 'sdk/appliance'
require_relative 'sdk/cloud/http'
require_relative 'sdk/cloud/locales'
require_relative 'sdk/cloud/session'
require_relative 'sdk/cloud/channel'

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

    # @return [Array<Appliance>] the appliances paired with the Miele account, reached by their module's name
    # @raise [ConfigurationError] without an account
    # @api public
    def self.appliances
      channel = cloud or raise ConfigurationError, 'the Miele account is needed to list its appliances'
      channel.devices.map { Appliance.new(it.host, fab: it.fab, module_host: it.host) }
    end

    # @return [Cloud::Channel, nil] the Miele account's cloud, nil without an e-mail or a saved token
    # @raise [ConfigurationError] without a country
    # @api public
    def self.cloud
      return @cloud if @cloud
      return unless config.email || config.cloud_token

      country = config.country or raise ConfigurationError, 'country is needed to reach the Miele cloud'
      @cloud = Cloud::Channel.new(Cloud::Session.new(Cloud::Locales.organization(country)))
    end

    # Changes the settings; the next request reaches the cloud with them.
    #
    # @yieldparam config [Configuration::Settings]
    # @return [void]
    # @api public
    def self.configure(&)
      super
      @cloud = nil
    end

    # Streams the changes the appliances push, until the block breaks or raises.
    #
    # @param hosts [Array<String>] addresses of the appliances to listen to
    # @yieldparam event [Events::Event]
    # @return [Enumerator::Lazy<Events::Event>, Object] the events without a block
    # @api public
    def self.events(hosts:, &) = Events::Listener.new(hosts:).each(&)
  end
end
