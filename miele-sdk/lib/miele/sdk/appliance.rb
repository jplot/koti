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
      include ObjectAccess

      # @return [String] address or +.local+ name of the appliance
      attr_reader :host

      # @param host [String] address or +.local+ name of the appliance
      # @param ident [Schema::DeviceIdentification, nil] its identity, read from it when not given
      # @return [Appliance] an instance of its family's class
      # @api public
      def self.for(host, ident: nil, **)
        probe = new(host, **)
        Families.claim(ident ||= probe.ident).new(host, **, ident:, fab: probe.fab)
      end

      # @param host [String] address or +.local+ name of the appliance
      # @param sleeper [#call] waits the given number of seconds
      # @param fab [String, nil] its fabrication number, when already known
      # @param module_host [String, nil] the mDNS name of its Wi-Fi module, which the cloud routes Dop1 by
      # @param ident [Schema::DeviceIdentification, nil] its identity, which gives its type and protocol without a read
      def initialize(host, sleeper: method(:sleep), fab: nil, module_host: nil, ident: nil)
        @host = host
        @identity = ident
        @sleeper = sleeper
        @fab = fab
        @module_host = module_host
        @local = Connection.local(host)
        @in_cloud = [] #: Array[String]
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
      def device_type = @device_type ||= Catalog::DEVICE_TYPES.fetch(identity.device_type, :unknown)

      # @return [Integer, nil] +ProtocolVersion+ of {#ident}: 2 on Dop1 appliances, 3 or 4 on DOP2 ones
      # @api public
      def protocol_version = @protocol_version ||= identity.protocol_version

      # @return [Symbol] {#protocol_version} named by {Catalog::PROTOCOLS}, or +:unknown+
      # @api public
      def protocol = Catalog::PROTOCOLS.fetch(protocol_version, :unknown)

      # @return [String, nil] +TechType+ of {#ident}'s device label, the model name
      # @api public
      def tech_type = @tech_type ||= identity.device_ident_label&.tech_type

      # @return [State]
      # @api public
      def state = State.new(device('State'), device_type, protocol_version:, tech_type:)

      # @param name [String] the name the Miele app shows
      # @api public
      def name=(name)
        send_request(:put, "/Devices/#{fab}/Ident", body: JSON.generate(DeviceName: name))
      end

      # Wakes the appliance from standby.
      #
      # @return [void]
      # @api public
      def wake = change(Schema::DeviceState.new(device_action: 2))

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
        Dop2.decode(send_request(:get, path).body)
      end

      # @param leaf [Dop2::Leaf]
      # @param with_index [Boolean] whether its indexes also go in the path, as the app's hood and coffee
      #   modules write; its oven, dishwasher and laundry modules leave them in the body only
      # @return [void]
      # @api public
      def write_dop2(leaf, with_index: false)
        path = dop2_path(leaf.unit, leaf.attribute)
        path += "?idx1=#{leaf.idx1}&idx2=#{leaf.idx2}" if with_index
        send_request(:put, path, body: Dop2.encode(leaf), kind: :dop2)
      end

      # Sends a Dop1 request, which hoods in +ProtocolVersion+ 2 answer instead of DOP2.
      #
      # @param request [String] built by {Dop1}
      # @return [String] the hood's answer: +{"Response": hex}+ to a read
      # @api public
      def dop1(request)
        send_request(:post, "/Devices/#{fab}/DOP/", body: JSON.generate(Request: request)).body
      end

      # Reads any JSON resource.
      #
      # @param path [String] absolute path
      # @return [Hash{String=>Object}]
      # @raise [Error] see {Connection.request}
      # @api public
      def get(path) = JSON.parse(send_request(:get, path).body)

      private

      # Local first: a resource the appliance answers 404 to goes, for good, to the cloud when an account is set.
      #
      # @param method [Symbol]
      # @param path [String]
      # @param body [String, nil]
      # @param kind [Symbol] +:json+ or +:dop2+
      # @return [Connection::Response]
      def send_request(method, path, body: nil, kind: :json)
        resource = path[%r{\A/Devices/\d+/([^/?]+)}, 1]
        return cloud_request(method, path, body, kind, resource) if @in_cloud.include?(resource)

        @local.request(method, path, body:, kind:)
      rescue NotFoundError
        raise unless resource && !@in_cloud.include?(resource) && Sdk.cloud

        @in_cloud << resource
        cloud_request(method, path, body, kind, resource)
      end

      # @return [Connection::Response]
      def cloud_request(method, path, body, kind, resource)
        cloud = Sdk.cloud or raise ConfigurationError, 'the Miele account is needed to reach the cloud'
        cloud.request(method, path, body:, kind:, host: resource == 'DOP' ? module_host : nil)
      end

      # @return [Schema::DeviceIdentification]
      def identity = @identity ||= ident

      # @return [String, nil]
      def module_host = @module_host ||= Sdk.cloud&.devices&.find { it.fab == fab }&.host

      # @param resource [String]
      # @return [Hash{String=>Object}]
      def device(resource) = get("/Devices/#{fab}/#{resource}")

      # @param request [Schema::DeviceState]
      # @return [Connection::Response]
      # @raise [RemoteControlDisabledError] if the appliance refuses commands
      def command(request) = send_request(:put, "/Devices/#{fab}/State", body: request.to_json)

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

      # @param condition [Object] what the app checks before the action
      # @param reason [String] what is missing
      # @return [void]
      # @raise [ActionUnavailableError] unless +condition+ holds
      def require!(condition, reason)
        raise ActionUnavailableError, reason unless condition
      end
    end
  end
end
