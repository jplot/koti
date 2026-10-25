# frozen_string_literal: true

require_relative 'sdk/version'
require_relative 'sdk/errors'
require_relative 'sdk/configuration'
require_relative 'sdk/connection'
require_relative 'sdk/client'
require_relative 'sdk/discovery'
require_relative 'sdk/pairing'
require_relative 'sdk/models'

# Namespace of the koti SDKs for the Philips Hue ecosystem.
module Hue
  # Unofficial Ruby SDK for the Philips Hue CLIP API v2, talking to one bridge
  # on the local network.
  #
  # @example Point the SDK at a bridge
  #   Hue::Sdk.configure do |config|
  #     config.host = '192.0.2.10'
  #     config.bridge_id = 'ECB5FAFFFE000001'
  #     config.application_key = ENV.fetch('HUE_APPLICATION_KEY')
  #   end
  module Sdk
    extend Configuration

    # Finds Hue bridges on the local network.
    #
    # @param timeout [Numeric] seconds to listen for answers (default: 3)
    # @param address [String] where to send the mDNS query (default: the mDNS multicast group)
    # @param port [Integer] destination port of the query (default: 5353)
    # @return [Array<Discovery::Bridge>]
    # @api public
    def self.discover(timeout: 3, address: '224.0.0.251', port: 5353) = Discovery.discover(timeout:, address:, port:)

    # Registers an application on the bridge; press its link button first.
    #
    # @param app_name [String] application name, at most 20 characters (default: +hue-sdk+)
    # @param instance_name [String] device name, truncated to 19 characters (default: the hostname)
    # @return [Pairing::Credentials]
    # @raise [LinkButtonNotPressedError] if the link button was not pressed in the last 30 seconds
    # @api public
    def self.pair(app_name: 'hue-sdk', instance_name: Socket.gethostname) = Pairing.pair(app_name:, instance_name:)

    # Returns the collection of a resource type, or one resource.
    #
    # @param type [String] CLIP v2 resource type (+light+, +room+…)
    # @param id [String, nil] resource id, or +nil+ for the collection
    # @return [Models::Base, Models::Base::Instance]
    # @api public
    def self.resource(type, id = nil)
      model = Models.lookup(type)
      id ? model::Instance.new(id) : model.new
    end

    # Defines the entry point of a resource type.
    #
    # @!macro [attach] resource_entry
    #   @!method $1(id = nil)
    #   @!scope class
    #   Returns the +$2+ collection, or one +$2+ resource when +id+ is given.
    #   @param id [String, nil] resource id
    #   @return [Models::$1, Models::$1::Instance]
    #   @api public
    # @param name [Symbol] entry point name
    # @param type [String] CLIP v2 resource type
    # @return [void]
    # @api private
    def self.entry(name, type) = define_singleton_method(name) { |id = nil| resource(type, id) }
    private_class_method :entry

    entry :Device, 'device'
    entry :DevicePower, 'device_power'
    entry :Light, 'light'
    entry :Room, 'room'
    entry :Scene, 'scene'
  end
end
