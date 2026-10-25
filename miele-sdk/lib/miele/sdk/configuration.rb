# frozen_string_literal: true

require 'singleton'

module Miele
  module Sdk
    # Provides SDK configuration management.
    #
    # Extended by {Miele::Sdk} to expose {#config} and {#configure} at the
    # module level.
    module Configuration
      # Singleton holding the settings of the household the SDK talks to.
      class Settings
        include Singleton

        # @return [String, nil] household GroupID, 16 hexadecimal digits
        attr_accessor :group_id

        # @return [String, nil] household GroupKey, 128 hexadecimal digits
        attr_accessor :group_key

        # @return [Integer] HTTP port of the appliances (default: 80)
        attr_accessor :port

        # @return [Numeric] seconds to wait for a connection (default: 5)
        attr_accessor :open_timeout

        # @return [Numeric] seconds to wait for a response (default: 10)
        attr_accessor :read_timeout

        # @return [Integer] TCP port the event listener binds (default: 18082)
        attr_accessor :listener_port

        # @return [String, nil] address announced to the appliances for pushed events
        #   (default: the local address that routes to them)
        attr_accessor :advertise_address

        # Initializes the settings with their defaults.
        #
        # @api private
        def initialize
          @port = 80
          @open_timeout = 5
          @read_timeout = 10
          @listener_port = 18_082
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
