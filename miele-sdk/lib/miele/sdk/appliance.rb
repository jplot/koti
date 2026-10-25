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
      def initialize(host)
        @host = host
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
      def device_type = Catalog::DEVICE_TYPES.fetch(ident['DeviceType'], :unknown)

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
    end
  end
end
