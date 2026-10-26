# frozen_string_literal: true

module Ajax
  module Sdk
    # Base class of every error raised by the SDK.
    class Error < StandardError; end

    # A setting is missing or malformed.
    class ConfigurationError < Error; end

    # A network connection failed or dropped.
    class ConnectionError < Error; end

    module Protobuf
      # A buffer could not be decoded against its schema.
      class DecodeError < Error; end
    end

    module Cloud
      # A gRPC path is not in the shipped method table.
      class UnknownMethodError < Error; end
    end

    module Http2
      # An HPACK header block or Huffman string is malformed.
      class CompressionError < Error; end

      # The connection closed while a stream was open.
      class ConnectionClosed < ConnectionError; end

      # The peer broke the HTTP/2 protocol.
      class ProtocolError < Error; end
    end
  end
end
