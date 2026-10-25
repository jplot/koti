# frozen_string_literal: true

module Hue
  module Sdk
    # Base class of every error raised by the SDK.
    class Error < StandardError; end

    # The bridge could not be reached, or the connection broke.
    class ConnectionError < Error; end

    # The bridge certificate is not signed by the Hue root CA, or does not
    # carry the configured bridge id.
    class TLSError < Error; end

    # The application key is missing, unknown to the bridge or revoked.
    class AuthenticationError < Error; end

    # The bridge answered with an error status.
    class ResponseError < Error
      # @return [Integer] HTTP status returned by the bridge
      attr_reader :status

      # @return [Array<String>] error descriptions returned by the bridge
      attr_reader :errors

      # @param status [Integer] HTTP status returned by the bridge
      # @param errors [Array<String>] error descriptions returned by the bridge
      # @api public
      def initialize(status, errors)
        @status = status
        @errors = errors
        super("bridge answered #{status}: #{errors.empty? ? 'no description' : errors.join('; ')}")
      end
    end

    # The requested resource does not exist on the bridge.
    class NotFoundError < ResponseError; end

    # The bridge refused the request because too many were sent.
    class RateLimitError < ResponseError; end
  end
end
