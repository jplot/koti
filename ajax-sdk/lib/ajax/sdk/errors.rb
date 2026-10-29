# frozen_string_literal: true

module Ajax
  module Sdk
    # Base class of every error raised by the SDK.
    class Error < StandardError; end

    # A setting is missing or malformed.
    class ConfigurationError < Error; end

    module Sia
      # A received frame is not valid DC-09: wrong CRC or length, unreadable, or not opened by the key.
      class FrameError < Error; end
    end

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

      # The gateway answered a call with its +failure+ (or +error+) member, or with neither member. +reason+ is
      # the member of the failure that is set, such as +:hub_offline+, or +:refused+ when none is.
      class RefusedError < Error
        # @return [Symbol] the machine-readable reason
        attr_reader :reason

        # @return [Data, nil] the whole failure, as a generated value
        attr_reader :failure

        # @return [Object, nil] what the failure gives for its reason, such as the devices in trouble
        attr_reader :details

        # @param reason [Symbol]
        # @param message [String]
        # @param failure [Data, nil]
        # @param details [Object, nil]
        def initialize(reason, message = nil, failure: nil, details: nil)
          @reason = reason
          @failure = failure
          @details = details
          super(message || reason.to_s)
        end
      end

      # A read (spaces, devices, …) was refused by the gateway. +reason+ is a symbol such as +:bad_request+.
      class ReadError < RefusedError; end

      # A command (arm, disarm, …) was refused by the hub. +reason+ is a symbol such as +:hub_offline+.
      class CommandError < RefusedError; end
    end
  end
end
