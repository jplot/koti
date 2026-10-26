# frozen_string_literal: true

require_relative 'sdk/version'
require_relative 'sdk/errors'
require_relative 'sdk/configuration'
require_relative 'sdk/cloud/schemas'
require_relative 'sdk/cloud/session'
require_relative 'sdk/cloud/client'

# Namespace of the koti SDKs for the Ajax ecosystem.
module Ajax
  # Unofficial Ruby SDK for Ajax alarm systems: SIA DC-09 events received on the
  # local network, and the cloud the official app talks to.
  #
  # @example Configure the account koti logs in with
  #   Ajax::Sdk.configure do |config|
  #     config.email = ENV.fetch('AJAX_EMAIL')
  #     config.password_sha256 = ENV.fetch('AJAX_PASSWORD_SHA256')
  #     config.totp_secret = ENV.fetch('AJAX_TOTP_SECRET')
  #   end
  module Sdk
    extend Configuration
  end
end
