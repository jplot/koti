# frozen_string_literal: true

require_relative '../sdk'

begin
  require 'ffi'
rescue LoadError
  raise Hue::Sdk::Error, "Entertainment streaming needs the ffi gem: add gem 'ffi' to your Gemfile"
end

require_relative 'entertainment/message'
require_relative 'entertainment/lib_ssl'
require_relative 'entertainment/dtls_socket'
require_relative 'entertainment/session'

module Hue
  module Sdk
    module Entertainment
      # Streaming for the instances of {Models::EntertainmentConfiguration}.
      module Streaming
        # Starts the configuration, yields a session to send frames, then stops
        # the configuration, even when the block raises. The bridge leaves the
        # lights on the last frame.
        #
        # @example Turn the first channel red for two seconds
        #   Hue::Sdk.EntertainmentConfiguration(id).stream do |session|
        #     100.times do
        #       session.write({ 0 => [1.0, 0.0, 0.0] })
        #       sleep 0.02
        #     end
        #   end
        #
        # @yieldparam session [Session]
        # @return [void]
        # @raise [AuthenticationError] if no client key is configured
        # @raise [ConnectionError] if the DTLS handshake fails
        # @raise [ResponseError] if the bridge refuses the start or the stop
        # @api public
        def stream
          config = Sdk.config
          key = config.client_key or raise AuthenticationError, 'client_key is not configured: pairing returns it'
          update(action: 'start')
          started = true
          socket = DtlsSocket.open(host: config.host.to_s, identity: config.application_key.to_s, psk: [key].pack('H*'))
          yield Session.new(socket, id)
        ensure
          socket&.close
          update(action: 'stop') if started
        end
      end
    end
  end
end

Hue::Sdk::Models::EntertainmentConfiguration::Instance.include(Hue::Sdk::Entertainment::Streaming)
