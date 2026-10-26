# frozen_string_literal: true

require_relative 'sdk/version'
require_relative 'sdk/errors'
require_relative 'sdk/configuration'
require_relative 'sdk/cloud/schemas'
require_relative 'sdk/cloud/session'
require_relative 'sdk/cloud/client'
require_relative 'sdk/sia'

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

    # Runs a {Sia::Receiver} with the configured +sia_*+ settings and yields each event it accepts; the
    # receiver stops when the block exits. Without a block, returns a lazy Enumerator of the events.
    #
    # @yieldparam event [Sia::Event]
    # @return [Enumerator::Lazy, nil]
    # @raise [ConfigurationError] when +sia_account+ is not set
    def self.sia_events
      return enum_for(:sia_events).lazy unless block_given?

      events = Queue.new
      receiver = sia_receiver { events << it }.start
      loop { yield events.pop }
    ensure
      receiver&.stop
    end

    def self.sia_receiver(&)
      account = config.sia_account or raise ConfigurationError, 'set sia_account'
      Sia::Receiver.new(host: config.sia_host, port: config.sia_port, account:, key: config.sia_key,
                        timeband: config.sia_timeband, &)
    end
    private_class_method :sia_receiver
  end
end
