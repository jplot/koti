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
      # Start of a user request on DOP2 2/1583, before its opcode, as ha-miele-at-lan sends it.
      USER_REQUEST = ['00100001062f00000000000100010700'].pack('H*').freeze
      private_constant :USER_REQUEST

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

      # @return [Hash{String=>Object}] identity: device type, protocol version, fabrication and module labels
      # @api public
      def ident = device('Ident')

      # @return [Hash{String=>Object}] links to the settings the appliance exposes
      # @api public
      def settings = device('Settings')

      # @return [Hash{String=>Object}] links to the service data of the appliance
      # @api public
      def service = device('Service')

      # @return [Hash{String=>Object}] software update state of the appliance itself
      # @raise [NotFoundError] on appliances that do not serve it
      # @api public
      def update = device('Update')

      # @return [Hash{String=>Object}] appliances this one notifies, and whether it notifies them
      # @api public
      def supervision = device('SuperVision')

      # @return [Hash{String=>Object}] the communication module's +/Info+
      # @api public
      def info = get('/Info')

      # @return [Hash{String=>Object}] the communication module's +/Host+
      # @api public
      def host_info = get('/Host')

      # @return [Hash{String=>Object}] software update state of the communication module
      # @api public
      def software_update = get('/Update/')

      # @return [Symbol] +DeviceType+ of {#ident} named by {Catalog::DEVICE_TYPES}, or +:unknown+
      # @api public
      def device_type = @device_type ||= Catalog::DEVICE_TYPES.fetch(ident['DeviceType'], :unknown)

      # @return [State]
      # @api public
      def state = State.new(device('State'), device_type)

      # @return [void]
      # @raise [ResponseError] if the appliance refuses (400)
      # @api public
      def start = command(ProcessAction: 1)

      # @return [void]
      # @raise [ResponseError] if the appliance refuses (400)
      # @api public
      def stop = command(ProcessAction: 2)

      # @return [void]
      # @raise [ResponseError] if the appliance refuses (400)
      # @api public
      def pause = command(ProcessAction: 3)

      # @return [void]
      # @api public
      def light_on = change(Light: 1)

      # @return [void]
      # @api public
      def light_off = change(Light: 2)

      # Wakes the appliance from standby.
      #
      # @return [void]
      # @api public
      def wake = change(DeviceAction: 2)

      # Switches the appliance on, waking it first when it sleeps.
      #
      # @return [void]
      # @raise [ResponseError] if the appliance refuses both ways of switching
      # @api public
      def power_on = power(4, 0x10)

      # @return [void]
      # @raise [ResponseError] if the appliance refuses both ways of switching
      # @api public
      def power_off = power(1, 0x13)

      # @param unit [Integer]
      # @param attribute [Integer]
      # @param idx1 [Integer]
      # @param idx2 [Integer]
      # @return [Dop2::Leaf]
      # @raise [Dop2::DecodeError]
      # @api public
      def dop2(unit, attribute, idx1: 0, idx2: 0)
        Dop2.decode(Connection.request(host, :get, dop2_path(unit, attribute, idx1, idx2)).body)
      end

      # The reference pads every DOP2 write to 32 bytes; shorter ones were never tried on an appliance.
      #
      # @param leaf [Dop2::Leaf] a leaf of scalar fields
      # @return [void]
      # @api public
      def write_dop2(leaf)
        path = dop2_path(leaf.unit, leaf.attribute, leaf.idx1, leaf.idx2)
        Connection.request(host, :put, path, body: Dop2.encode(leaf).ljust(32, ' '))
      end

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

      # @param body [Hash{Symbol=>Integer}]
      # @return [Connection::Response]
      # @raise [RemoteControlDisabledError] if the appliance refuses commands
      def command(body) = Connection.request(host, :put, "/Devices/#{fab}/State", body: JSON.generate(body))

      # The appliance answers 400 to a write that changes nothing, such as
      # switching on a light already on.
      #
      # @param body [Hash{Symbol=>Integer}]
      # @return [void]
      def change(body)
        command(body)
      rescue ResponseError => e
        raise unless e.status == 400
      end

      # @return [String]
      def dop2_path(unit, attribute, idx1, idx2) = "/Devices/#{fab}/DOP2/#{unit}/#{attribute}?idx1=#{idx1}&idx2=#{idx2}"

      # A sleeping appliance answers 500 to the state write on 2/1586; the
      # reference wakes it, waits 3 s and retries, twice at most, then sends
      # the switch opcode on 2/1583.
      #
      # @param state [Integer] appliance state: 4 on, 1 off
      # @param opcode [Integer] user request switching the same way
      # @return [void]
      def power(state, opcode)
        leaf = Dop2::Leaf.new(unit: 2, attribute: 1586, idx1: 0, idx2: 0,
                              fields: { 1 => Dop2::Field.new(type: :e8, value: state) })
        3.times do |attempt|
          rouse if attempt.positive?
          return write_dop2(leaf)
        rescue ResponseError => e
          break unless e.status == 500
        end
        Connection.request(host, :put, dop2_path(2, 1583, 0, 0), body: USER_REQUEST + opcode.chr + (' ' * 15))
      end

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
