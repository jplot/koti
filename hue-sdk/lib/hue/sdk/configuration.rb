# frozen_string_literal: true

require 'singleton'

module Hue
  module Sdk
    # Provides SDK configuration management.
    #
    # Extended by {Hue::Sdk} to expose {#config} and {#configure} at the
    # module level.
    module Configuration
      # Hue root CA (+CN=root-bridge+) that signs every bridge certificate.
      DEFAULT_CA_FILE = File.expand_path('certificates/root-bridge.pem', File.dirname(__FILE__))

      # Singleton holding the settings of the one bridge the SDK talks to.
      class Settings
        include Singleton

        # @return [String, nil] IP address or hostname of the bridge
        attr_accessor :host

        # @return [Integer] HTTPS port of the bridge (default: 443)
        attr_accessor :port

        # @return [String, nil] bridge identifier, matched against the CN of its certificate
        attr_accessor :bridge_id

        # @return [String, nil] application key sent as +hue-application-key+
        attr_accessor :application_key

        # @return [String] PEM file of the CA the bridge certificate must chain to
        #   (default: the Hue root CA embedded in the gem)
        attr_accessor :ca_file

        # @return [String, nil] client key (hex) used as the entertainment PSK
        attr_accessor :client_key

        # @return [Numeric] seconds to wait for a connection (default: 5)
        attr_accessor :open_timeout

        # @return [Numeric] seconds to wait for a response (default: 10)
        attr_accessor :read_timeout

        # @return [Numeric] seconds of event stream silence before reconnecting (default: 300)
        attr_accessor :event_read_timeout

        # Initializes the settings with their defaults.
        #
        # @api private
        def initialize
          @port = 443
          @open_timeout = 5
          @read_timeout = 10
          @event_read_timeout = 300
          @ca_file = DEFAULT_CA_FILE
        end
      end

      # Returns the singleton settings.
      #
      # @return [Settings]
      # @api public
      def config = Settings.instance

      # Configures the SDK via a block.
      #
      # @yieldparam config [Settings] the settings to modify
      # @return [void]
      # @api public
      def configure = yield(config)
    end
  end
end
