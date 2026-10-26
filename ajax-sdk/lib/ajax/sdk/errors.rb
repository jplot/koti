# frozen_string_literal: true

module Ajax
  module Sdk
    # Base class of every error raised by the SDK.
    class Error < StandardError; end

    # A setting is missing or malformed.
    class ConfigurationError < Error; end

    module Cloud
      # A gRPC path is not in the shipped method table.
      class UnknownMethodError < Error; end

      # A message name is not in the shipped schemas.
      class UnknownMessageError < Error; end

      # The account could not be logged in. +reason+ is a symbol such as +:invalid_credentials+.
      class AuthenticationError < Error
        # @return [Symbol] the machine-readable reason
        attr_reader :reason

        # @param reason [Symbol]
        # @param message [String]
        def initialize(reason, message = nil)
          @reason = reason
          super(message || reason.to_s)
        end
      end

      # A state-changing command was blocked because the client is configured read-only.
      class ReadOnlyError < Error; end

      # A read (spaces, devices, …) was refused by the gateway. +reason+ is a symbol such as +:bad_request+.
      class ReadError < Error
        # @return [Symbol] the machine-readable reason
        attr_reader :reason

        # @param reason [Symbol]
        # @param message [String]
        def initialize(reason, message = nil)
          @reason = reason
          super(message || reason.to_s)
        end
      end

      # A command (arm, disarm, …) was refused by the hub. +reason+ is a symbol such as +:hub_offline+.
      class CommandError < Error
        # @return [Symbol] the machine-readable reason
        attr_reader :reason

        # @param reason [Symbol]
        # @param message [String]
        def initialize(reason, message = nil)
          @reason = reason
          super(message || reason.to_s)
        end
      end
    end
  end
end
