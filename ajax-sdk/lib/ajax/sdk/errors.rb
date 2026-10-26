# frozen_string_literal: true

module Ajax
  module Sdk
    # Base class of every error raised by the SDK.
    class Error < StandardError; end

    # A setting is missing or malformed.
    class ConfigurationError < Error; end
  end
end
