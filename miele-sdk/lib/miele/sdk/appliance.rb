# frozen_string_literal: true

require 'json'

module Miele
  module Sdk
    # One appliance and the REST resources it serves.
    #
    # @example Read what an appliance is
    #   oven = Miele::Sdk.appliance('192.0.2.20')
    #   oven.device_type # => :oven_microwave
    class Appliance
      # @return [String] address or +.local+ name of the appliance
      attr_reader :host

      # @param host [String] address or +.local+ name of the appliance
      # @param sleeper [#call] waits the given number of seconds
      def initialize(host, sleeper: method(:sleep))
        @host = host
        @sleeper = sleeper
      end

      # @return [String] fabrication number, which names the appliance in every device path
      # @raise [Error] see {Connection.request}
      # @api public
      def fab = @fab ||= get('/Devices/').keys.fetch(0)

      # @return [Schema::DeviceIdentification] identity: device type, protocol version, fabrication and module labels
      # @api public
      def ident = Schema::DeviceIdentification.from(device('Ident'))

      # @return [Hash{String=>Object}] links to the settings the appliance exposes
      # @api public
      def settings = device('Settings')

      # @return [Hash{String=>Object}] links to the service data of the Wi-Fi module, which it serves locally
      # @api public
      def service = device('Service')

      # @return [Hash{String=>Object}] the services the Miele app reads (camera, remote update, Con@ctivity…)
      # @raise [NotFoundError] on EK057 and EK039W modules, which do not serve it locally
      # @api public
      def services = device('services')

      # @return [Hash{String=>Object}] software update state of the appliance itself
      # @raise [NotFoundError] on appliances that do not serve it
      # @api public
      def update = device('Update')

      # @return [Schema::SuperVision] appliances this one notifies, and whether it notifies them
      # @api public
      def supervision = Schema::SuperVision.from(device('SuperVision'))

      # @return [Hash{String=>Object}] the communication module's +/Info+
      # @api public
      def info = get('/Info')

      # @return [Hash{String=>Object}] the communication module's +/Host+
      # @api public
      def host_info = get('/Host')

      # @return [Schema::ModuleUpdateInfo] software update state of the communication module
      # @api public
      def software_update = Schema::ModuleUpdateInfo.from(get('/Update/'))

      # @return [Symbol] +DeviceType+ of {#ident} named by {Catalog::DEVICE_TYPES}, or +:unknown+
      # @api public
      def device_type = @device_type ||= Catalog::DEVICE_TYPES.fetch(ident.device_type, :unknown)

      # @return [Integer, nil] +ProtocolVersion+ of {#ident}: 2 on Dop1 appliances, 3 or 4 on DOP2 ones
      # @api public
      def protocol_version = @protocol_version ||= ident.protocol_version

      # @return [Symbol] {#protocol_version} named by {Catalog::PROTOCOLS}, or +:unknown+
      # @api public
      def protocol = Catalog::PROTOCOLS.fetch(protocol_version, :unknown)

      # @return [String, nil] +TechType+ of {#ident}'s device label, the model name
      # @api public
      def tech_type = @tech_type ||= ident.device_ident_label&.tech_type

      # @return [State]
      # @api public
      def state = State.new(device('State'), device_type, protocol_version:, tech_type:)

      # Wakes the appliance from standby.
      #
      # @return [void]
      # @api public
      def wake = change(Schema::DeviceState.new(device_action: 2))

      # Switches the appliance on as the app's oven module does, waking it first when it sleeps. The app's
      # other families switch on in their own way.
      #
      # @return [void]
      # @raise [ResponseError] if the appliance still refuses after three attempts
      # @api public
      def power_on
        3.times do |attempt|
          rouse if attempt.positive?
          return write_dop2(power_leaf(4))
        rescue ResponseError => e
          raise unless e.status == 500 && attempt < 2
        end
      end

      # @return [void]
      # @raise [ResponseError] if the appliance refuses
      # @api public
      def power_off = write_dop2(power_leaf(1))

      # Without an index, the read is the one the app's live observation sends; its one-shot reads give
      # +idx1: 0, idx2: 0+ and its polls +idx1: 0, idx2: 1+.
      #
      # @param unit [Integer]
      # @param attribute [Integer]
      # @param idx1 [Integer, nil]
      # @param idx2 [Integer, nil]
      # @return [Dop2::Leaf]
      # @raise [Dop2::DecodeError]
      # @api public
      def dop2(unit, attribute, idx1: nil, idx2: nil)
        path = dop2_path(unit, attribute)
        path += "?idx1=#{idx1.to_i}&idx2=#{idx2.to_i}" unless idx1.nil? && idx2.nil?
        Dop2.decode(Connection.request(host, :get, path).body)
      end

      # The reference pads every DOP2 write to 32 bytes; shorter ones were never tried on an appliance.
      #
      # @param leaf [Dop2::Leaf]
      # @param with_index [Boolean] whether its indexes also go in the path, as the app's hood and coffee
      #   modules write; its oven, dishwasher and laundry modules leave them in the body only
      # @return [void]
      # @api public
      def write_dop2(leaf, with_index: false)
        path = dop2_path(leaf.unit, leaf.attribute)
        path += "?idx1=#{leaf.idx1}&idx2=#{leaf.idx2}" if with_index
        Connection.request(host, :put, path, body: Dop2.encode(leaf).ljust(32, ' '))
      end

      # Sends a Dop1 request, which hoods in +ProtocolVersion+ 2 answer instead of DOP2.
      #
      # @param request [String] built by {Dop1}
      # @return [String] the hood's answer: +{"Response": hex}+ to a read
      # @api public
      def dop1(request)
        Connection.request(host, :post, "/Devices/#{fab}/DOP/", body: JSON.generate(Request: request)).body
      end

      # @param level [Integer] 0 (off) to 3, 4 (boost) or 5 (interval)
      # @raise [ArgumentError] if the level is out of range
      # @api public
      def fan_level=(level)
        tolerating_no_op { dop1(Dop1.fan_level(level)) }
      end

      # @param minutes [Integer] 0, 5 or 15
      # @raise [ArgumentError] for any other duration
      # @api public
      def fan_run_on_time=(minutes)
        tolerating_no_op { dop1(Dop1.fan_run_on_time(minutes)) }
      end

      # @param on [Boolean]
      # @api public
      def main_light=(on)
        tolerating_no_op { dop1(Dop1.main_light(on)) }
      end

      # @param pf_id [Integer] programming function id: 40010 and 40011 are the current grease and charcoal filter
      #   limits; writing 1 to 40012 or 40013 resets their operating hours
      # @return [Integer, nil] nil when the hood does not expose that setting
      # @api public
      def setting(pf_id) = Dop1.setting_value(JSON.parse(dop1(Dop1.setting(pf_id))).fetch('Response'))

      # @param pf_id [Integer] programming function id
      # @param value [Integer] unsigned 32-bit value
      # @return [void]
      # @raise [ArgumentError] if the id or the value is out of range
      # @api public
      def write_setting(pf_id, value) = tolerating_no_op { dop1(Dop1.write_setting(pf_id, value)) }

      # Reads any JSON resource.
      #
      # @param path [String] absolute path
      # @return [Hash{String=>Object}]
      # @raise [Error] see {Connection.request}
      # @api public
      def get(path) = JSON.parse(Connection.request(host, :get, path).body)

      private

      # @param resource [String]
      # @return [Hash{String=>Object}]
      def device(resource) = get("/Devices/#{fab}/#{resource}")

      # @param request [Schema::DeviceState]
      # @return [Connection::Response]
      # @raise [RemoteControlDisabledError] if the appliance refuses commands
      def command(request) = Connection.request(host, :put, "/Devices/#{fab}/State", body: request.to_json)

      # @param request [Schema::DeviceState]
      # @return [void]
      def change(request) = tolerating_no_op { command(request) }

      # The appliance answers 400 to a write that changes nothing, such as
      # switching on a light already on.
      #
      # @yield the write
      # @return [void]
      def tolerating_no_op
        yield
      rescue ResponseError => e
        raise unless e.status == 400
      end

      # @return [String]
      def dop2_path(unit, attribute) = "/Devices/#{fab}/DOP2/#{unit}/#{attribute}"

      # The appliance state on 2/1586: 4 switches on, 1 off.
      #
      # @param state [Integer]
      # @return [Dop2::Leaf]
      def power_leaf(state)
        Dop2::Leaf.new(unit: 2, attribute: 1586, idx1: 0, idx2: 0,
                       fields: { 1 => Dop2::Field.new(type: :e8, value: state) })
      end

      # A sleeping appliance answers 500 to the state write; the app then sends DeviceAction 2, waits 3 s and
      # tries again, with no limit: three attempts here.
      #
      # @return [void]
      def rouse
        begin
          wake
        rescue ResponseError
          nil
        end
        @sleeper.call(3)
      end
    end
  end
end
