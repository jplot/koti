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
  end
end
