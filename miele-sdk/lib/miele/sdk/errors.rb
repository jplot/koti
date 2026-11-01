# frozen_string_literal: true

module Miele
  module Sdk
    # Base class of every error raised by the SDK.
    class Error < StandardError; end

    # The household GroupID or GroupKey is missing or malformed.
    class ConfigurationError < Error; end

    # The appliance could not be reached, or the connection broke.
    class ConnectionError < Error; end

    # A response is not signed by the household key: it was altered, or does
    # not come from an appliance of the household.
    class SignatureError < Error; end

    # The appliance refused a read: the household key does not match its own.
    class AuthenticationError < Error; end

    # The appliance answered with an error status.
    class ResponseError < Error
      # @return [Integer] HTTP status returned by the appliance
      attr_reader :status

      # @param status [Integer] HTTP status returned by the appliance
      # @param message [String] explanation
      # @api public
      def initialize(status, message = "appliance answered #{status}")
        @status = status
        super(message)
      end
    end

    # The appliance has no such resource.
    class NotFoundError < ResponseError; end

    # The appliance refused a command.
    class RemoteControlDisabledError < ResponseError; end

    # An action the appliance does not offer now, refused before anything is sent, as the Miele app refuses it.
    class ActionUnavailableError < Error; end

    # The appliance answered a Dop1 write with an Ack other than success (1), which the Miele app reports as
    # settings not accepted.
    class NotAcceptedError < Error; end

    # The appliance took an action's write but did not show its effect within the 15 s the Miele app waits for it
    # (ActionExecutionTimeout), or showed a state without a value the app reads on the way; the app reports
    # either as a failed action.
    class ActionFailedError < Error; end
  end
end
