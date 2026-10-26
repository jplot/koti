# frozen_string_literal: true

module Ajax
  module Sdk
    # Base class of every error raised by the SDK.
    class Error < StandardError; end

    # A setting is missing or malformed.
    class ConfigurationError < Error; end

    module Protobuf
      # A buffer could not be decoded against its schema.
      class DecodeError < Error; end
    end

    module Cloud
      # A gRPC path is not in the shipped method table.
      class UnknownMethodError < Error; end
    end
  end
end
