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

          # @return [String] +host:port+ of the gRPC service that lists the homes
          #   (default: +api.account.meethue.com:443+)
          attr_accessor :grpc_target

          # @return [Object, nil] +GRPC::Core::ChannelCredentials+, or +:this_channel_is_insecure+ for a test server
          #   (default: nil, TLS with the system's roots)
          attr_accessor :grpc_credentials

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
            @open_timeout = 5
            @read_timeout = 10
          end
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
