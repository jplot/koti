# frozen_string_literal: true

module Hue
  module Sdk
    # Base class of every error raised by the SDK.
    class Error < StandardError; end

    # The bridge or the Hue cloud could not be reached, or the connection broke.
    class ConnectionError < Error; end

    # The bridge certificate is not signed by the Hue root CA, or does not
    # carry the configured bridge id; or the certificate of the Hue Secure broker does not chain to the root the app
    # pins, or names another host.
    class TLSError < Error; end

    # The application key is missing, unknown to the bridge or revoked; or the Hue account has no token, or
    # refuses it.
    class AuthenticationError < Error; end

    # The link button of the bridge was not pressed before pairing.
    class LinkButtonNotPressedError < Error; end

    # The bridge, or the Hue cloud, answered with an error status.
    class ResponseError < Error
      # @return [Integer] HTTP status returned by the bridge
      attr_reader :status

      # @return [Array<String>] error descriptions returned by the bridge
      attr_reader :errors

      # @param status [Integer] HTTP status returned by the bridge
      # @param errors [Array<String>] error descriptions returned by the bridge
      # @param source [String] who answered
      # @api public
      def initialize(status, errors, source: 'bridge')
        @status = status
        @errors = errors
        super("#{source} answered #{status}: #{errors.empty? ? 'no description' : errors.join('; ')}")
      end
    end

    # The requested resource does not exist on the bridge.
    class NotFoundError < ResponseError; end

    # The bridge refused the request because too many were sent.
    class RateLimitError < ResponseError
      # @return [Float, nil] seconds the bridge asked to wait (Retry-After), nil when it named none, and from the Hue
      #   cloud, pairing or the event stream
      attr_reader :retry_after

      # @param status [Integer]
      # @param errors [Array<String>]
      # @param retry_after [Float, nil]
      # @api public
      def initialize(status, errors, retry_after: nil, **)
        @retry_after = retry_after
        super(status, errors, **)
      end
    end
  end
end
