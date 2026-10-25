# frozen_string_literal: true

require_relative 'sdk/version'
require_relative 'sdk/errors'
require_relative 'sdk/configuration'
require_relative 'sdk/connection'

# Namespace of the koti SDKs for the Philips Hue ecosystem.
module Hue
  # Unofficial Ruby SDK for the Philips Hue CLIP API v2, talking to one bridge
  # on the local network.
  #
  # @example Point the SDK at a bridge
  #   Hue::Sdk.configure do |config|
  #     config.host = '192.0.2.10'
  #     config.bridge_id = 'ECB5FAFFFE000001'
  #     config.application_key = ENV.fetch('HUE_APPLICATION_KEY')
  #   end
  module Sdk
    extend Configuration
  end
end
