# frozen_string_literal: true

require 'singleton'
require 'socket'
require 'zlib'

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

        # Stable from one run to the next, so that appliances recognize this host and
        # a run cut short leaves subscriptions the next one withdraws.
        #
        # @return [String] fabrication number this host takes in the household: +000999+ then six
        #   digits from the host name
        attr_accessor :listener_fab

        # @return [String, nil] ISO code of the country the Miele account is registered in, which picks its cloud
        attr_accessor :country

        # @return [String, nil] e-mail address of the Miele account
        attr_accessor :email

        # @return [String, nil] password of the Miele account, sent as is to the cloud's login, as the app sends it
        attr_accessor :password

        # @return [String, nil] OAuth client id of the Miele app, for the countries that log in through CIAM
        attr_accessor :ciam_client_id

        # @return [String, nil] a token saved from {Cloud::Token#to_json}, to start without logging in
        attr_accessor :cloud_token

        # A CIAM login needs a browser, so a program that restarts keeps its token there.
        #
        # @return [String, nil] file the session reads its token from and writes each new one to (mode 0600)
        attr_accessor :token_file

        # @return [String] where the app reads the cloud of each country (default:
        #   +https://rest-eu.domestic.miele-iot.com+)
        attr_accessor :locales_host

        # Initializes the settings with their defaults.
        #
        # @api private
        def initialize
          @port = 80
          @open_timeout = 5
          @read_timeout = 10
          @listener_port = 18_082
          @listener_fab = format('000999%06d', Zlib.crc32(Socket.gethostname) % 1_000_000)
          @locales_host = 'https://rest-eu.domestic.miele-iot.com'
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
