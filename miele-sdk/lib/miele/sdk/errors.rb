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

    # The appliance answered with an error status, or a read without a body.
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

    # Appliances the events listener could not enroll, or could not withdraw: these keep its subscriptions until
    # a later run withdraws them.
    class SubscriptionError < Error
      # @return [Hash{String=>StandardError}] the error of each appliance, by host
      attr_reader :failures

      # @param action [String] what failed: +enroll+ or +withdraw+
      # @param failures [Hash{String=>StandardError}] the error of each appliance, by host
      # @api public
      def initialize(action, failures)
        @failures = failures
        super("could not #{action} #{failures.map { |host, error| "#{host} (#{error.message})" }.join(', ')}")
      end
    end

    # The appliance has no such resource.
    class NotFoundError < ResponseError; end

    # The appliance refused a command.
    class RemoteControlDisabledError < ResponseError; end

    # The appliance's protocol or state gives no request to send for this action, such as a DOP2 leaf on a Dop1
    # appliance or a parameter with no program selected: nothing is sent. Whether the Miele app offers an action
    # is the appliance's predicates' to tell, never a refusal.
    class ActionUnavailableError < Error; end

    # The appliance answered a write without the success the Miele app looks for: a Dop1 Ack other than 1, which
    # it reports as settings not accepted, or a hood's wake answered without "Success".
    class NotAcceptedError < Error; end

    # The appliance took an action's write but did not show its effect within the time the Miele app waits for it
    # (15 s, ActionExecutionTimeout; a minute for a DOP2 hood's wake), or showed a state without a value the app
    # reads on the way; the app reports either as a failed action.
    class ActionFailedError < Error; end
  end
end
