# frozen_string_literal: true

require 'singleton'

module Hue
  module Sdk
    module Secure
      # Settings of the Hue account's cloud, extended by {Secure}.
      module Configuration
        # Singleton holding the settings of the one account the SDK talks to.
        class Settings
          include Singleton

          # @return [String, nil] Auth0 client id the account logs in with: the Hue app's, which the gem does not ship
          attr_accessor :client_id

          # @return [String, nil] a token saved by {Token#to_json}, read before +token_file+
          attr_accessor :token

          # @return [String, nil] file the token is read from and written to, in mode 0600
          attr_accessor :token_file

          # @return [String] host of the OpenID discovery (default: +https://login.meethue.com+)
          attr_accessor :login_url

          # @return [String] address the paths of {Client} are under (default: +https://api.account.meethue.com+)
          attr_accessor :api_url

          # @return [String] address of the automatic responses of a doorbell
          #   (default: +https://automaticresponses.eu.secure.meethue.com+)
          attr_accessor :auto_responses_url

          # @return [String] +host:port+ of the gRPC service that lists the homes
          #   (default: +api.account.meethue.com:443+)
          attr_accessor :grpc_target

          # @return [Object, nil] +GRPC::Core::ChannelCredentials+, or +:this_channel_is_insecure+ for a test server
          #   (default: nil, TLS with the system's roots)
          attr_accessor :grpc_credentials

          # @return [String] host of the MQTT broker that {Follow} follows a home on
          #   (default: +mqtt.eu.secure.meethue.com+)
          attr_accessor :mqtt_host

          # @return [Integer] port of the MQTT broker, which takes ALPN +mqtt+ (default: 443)
          attr_accessor :mqtt_port

          # @return [String] PEM file of the one root the broker's certificate must chain to (default: Amazon Root CA 1,
          #   the root the app pins)
          attr_accessor :mqtt_ca_file

          # @return [String] AWS region of Kinesis Video, which clips download from (default: +eu-west-1+, the app's)
          attr_accessor :kinesis_region

          # @param url [String, nil] address of Kinesis Video's control plane; nil for the region's own
          attr_writer :kinesis_url

          # @return [Numeric] seconds to wait for a connection (default: 5)
          attr_accessor :open_timeout

          # @return [Numeric] seconds to wait for a response (default: 10)
          attr_accessor :read_timeout

          # Initializes the settings with their defaults.
          #
          # @api private
          def initialize
            @login_url = 'https://login.meethue.com'
            @api_url = 'https://api.account.meethue.com'
            @grpc_target = 'api.account.meethue.com:443'
            @auto_responses_url = 'https://automaticresponses.eu.secure.meethue.com'
            @mqtt_host = 'mqtt.eu.secure.meethue.com'
            @mqtt_port = 443
            @mqtt_ca_file = File.expand_path('../certificates/amazon-root-ca-1.pem', File.dirname(__FILE__))
            @kinesis_region = 'eu-west-1'
            @open_timeout = 5
            @read_timeout = 10
          end

          # @return [String] address of Kinesis Video's control plane (default: the region's own, as the app reaches
          #   it in eu-west-1)
          def kinesis_url = @kinesis_url || "https://kinesisvideo.#{kinesis_region}.amazonaws.com"
        end

        # Returns the singleton settings.
        #
        # @return [Settings]
        # @api public
        def config = Settings.instance

        # Configures the account via a block.
        #
        # @yieldparam config [Settings] the settings to modify
        # @return [void]
        # @api public
        def configure = yield(config)
      end
    end
  end
end
