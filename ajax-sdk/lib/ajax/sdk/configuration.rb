# frozen_string_literal: true

require 'digest'
require 'singleton'
require 'socket'

module Ajax
  module Sdk
    # Provides SDK configuration management.
    #
    # Extended by {Ajax::Sdk} to expose {#config} and {#configure} at the
    # module level.
    module Configuration
      # Singleton holding the account, the cloud endpoint and the SIA receiver settings.
      class Settings
        include Singleton

        # @return [String, nil] e-mail of the Ajax account koti logs in with
        attr_accessor :email

        # @return [String, nil] password of that account, when its hash is not given instead
        attr_accessor :password

        # @return [String, nil] lowercase hexadecimal SHA-256 of the password, what the app sends
        attr_accessor :password_sha256

        # @return [String, nil] base32 secret of the account's two-factor authentication
        attr_accessor :totp_secret

        # @return [String, nil] uppercase hexadecimal session token of an earlier login
        attr_accessor :session_token

        # @return [String, nil] hexadecimal user id that goes with {#session_token}
        attr_accessor :user_id

        # @return [String] host of the Ajax mobile gateway (default: mobile-gw.prod.ajax.systems)
        attr_accessor :grpc_host

        # @return [Integer] TLS port of the mobile gateway (default: 443)
        attr_accessor :grpc_port

        # @return [String, nil] CA bundle that verifies the gateway, instead of the system one
        attr_accessor :ca_file

        # @return [String] app version announced to the cloud (default: 3.59, the analysed app)
        attr_accessor :client_version

        # The app sends ANDROID_ID followed by +_Ajax+; koti keeps that shape with an id of its own,
        # stable from one run to the next.
        #
        # @return [String] device id announced to the cloud
        attr_accessor :client_device_id

        # @return [String] device model announced to the cloud (default: koti ajax-sdk)
        attr_accessor :client_device_model

        # When true, every state-changing command (arm, disarm, …) raises before anything is sent.
        # It guards the live specs, which must never change a real alarm's state.
        #
        # @return [Boolean] whether commands are refused (default: false)
        attr_accessor :read_only

        # @return [Numeric] seconds to wait for an answer (default: 30)
        attr_accessor :read_timeout

        # @return [String] address the SIA receiver binds (default: 0.0.0.0)
        attr_accessor :sia_host

        # @return [Integer] TCP port the SIA receiver binds (default: 18083)
        attr_accessor :sia_port

        # @return [String, nil] SIA account (object number) set on the hub
        attr_accessor :sia_account

        # @return [String, nil] SIA encryption key set on the hub
        attr_accessor :sia_key

        # @return [Array(Integer, Integer)] seconds a SIA timestamp may lag behind or run ahead
        #   (default: 40 and 20)
        attr_accessor :sia_timeband

        # Initializes the settings with their defaults.
        #
        # @api private
        def initialize
          @grpc_host = 'mobile-gw.prod.ajax.systems'
          @grpc_port = 443
          @client_version = '3.59'
          @client_device_id = "#{Digest::SHA256.hexdigest(Socket.gethostname)[0, 16]}_Ajax"
          @client_device_model = 'koti ajax-sdk'
          @read_only = false
          @read_timeout = 30
          @sia_host = '0.0.0.0'
          @sia_port = 18_083
          @sia_timeband = [40, 20]
        end

        # Hidden secrets: the password, its hash, the TOTP secret, the session token and the SIA key.
        SECRETS = %i[@password @password_sha256 @totp_secret @session_token @sia_key].freeze

        # @return [String] the settings with every secret redacted
        def inspect
          shown = instance_variables.reject { |name| SECRETS.include?(name) }
                                    .map { |name| "#{name}=#{instance_variable_get(name).inspect}" }
          "#<#{self.class.name} #{shown.join(', ')}, secrets redacted>"
        end
      end

      # @api private
      CLOUD_LOCK = Mutex.new

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

      # Returns the cloud client, built once from the current settings.
      #
      # @return [Cloud::Client]
      # @api public
      def cloud = CLOUD_LOCK.synchronize { @cloud ||= Cloud::Client.new }
    end
  end
end
