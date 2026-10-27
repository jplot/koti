# frozen_string_literal: true

require_relative 'sdk/version'
require_relative 'sdk/errors'
require_relative 'sdk/configuration'
require_relative 'sdk/connection'
require_relative 'sdk/client'
require_relative 'sdk/discovery'
require_relative 'sdk/pairing'
require_relative 'sdk/schema'
require_relative 'sdk/models'
require_relative 'sdk/events'

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
    # @param timeout [Numeric] seconds to listen for answers (default: 4, time for queries at 0, 1 and 3 seconds)
    # @param address [String] where to send the mDNS query (default: the mDNS multicast group)
    # @param port [Integer] destination port of the query (default: 5353)
    # @return [Array<Discovery::Bridge>]
    # @api public
    def self.discover(timeout: 4, address: '224.0.0.251', port: 5353) = Discovery.discover(timeout:, address:, port:)

    # Registers an application on the bridge; press its link button first.
    #
    # @param app_name [String] application name, at most 20 characters (default: +hue-sdk+)
    # @param instance_name [String] device name, truncated to 19 characters (default: the hostname)
    # @return [Pairing::Credentials]
    # @raise [LinkButtonNotPressedError] if the link button was not pressed in the last 30 seconds
    # @api public
    def self.pair(app_name: 'hue-sdk', instance_name: Socket.gethostname) = Pairing.pair(app_name:, instance_name:)

    # Follows what changes on the bridge, reconnecting when the stream breaks.
    #
    # @example Print every light switched on or off
    #   Hue::Sdk.events { |event| puts event.resource_id if event.changes.key?('on') }
    #
    # @yieldparam event [Event]
    # @return [Enumerator::Lazy<Event>] without a block; with one, blocks until the block breaks
    # @raise (see Events::Stream#each)
    # @api public
    def self.events(&block)
      stream = Events::Stream.new
      block ? stream.each(&block) : stream.to_enum.lazy
    end

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

    entry :BehaviorInstance, 'behavior_instance'
    entry :BehaviorScript, 'behavior_script'
    entry :BehaviorScriptFormula, 'behavior_script_formula'
    entry :BellButton, 'bell_button'
    entry :Bridge, 'bridge'
    entry :BridgeHome, 'bridge_home'
    entry :Button, 'button'
    entry :CameraMotion, 'camera_motion'
    entry :Clip, 'clip'
    entry :Contact, 'contact'
    entry :ConvenienceAreaMotion, 'convenience_area_motion'
    entry :Device, 'device'
    entry :DevicePower, 'device_power'
    entry :DeviceSoftwareUpdate, 'device_software_update'
    entry :Entertainment, 'entertainment'
    entry :EntertainmentConfiguration, 'entertainment_configuration'
    entry :GeofenceClient, 'geofence_client'
    entry :Geolocation, 'geolocation'
    entry :GroupedLight, 'grouped_light'
    entry :GroupedLightLevel, 'grouped_light_level'
    entry :GroupedMotion, 'grouped_motion'
    entry :Homekit, 'homekit'
    entry :Light, 'light'
    entry :LightLevel, 'light_level'
    entry :Matter, 'matter'
    entry :MatterFabric, 'matter_fabric'
    entry :Motion, 'motion'
    entry :MotionAreaCandidate, 'motion_area_candidate'
    entry :MotionAreaConfiguration, 'motion_area_configuration'
    entry :PowerOutputConfiguration, 'power_output_configuration'
    entry :RelativeRotary, 'relative_rotary'
    entry :Room, 'room'
    entry :Scene, 'scene'
    entry :SecurityAreaMotion, 'security_area_motion'
    entry :ServiceGroup, 'service_group'
    entry :SmartScene, 'smart_scene'
    entry :Speaker, 'speaker'
    entry :SwitchInputConfiguration, 'switch_input_configuration'
    entry :Tamper, 'tamper'
    entry :Temperature, 'temperature'
    entry :WifiConnectivity, 'wifi_connectivity'
    entry :ZgpConnectivity, 'zgp_connectivity'
    entry :ZigbeeConnectivity, 'zigbee_connectivity'
    entry :ZigbeeDeviceDiscovery, 'zigbee_device_discovery'
    entry :Zone, 'zone'
  end
end
