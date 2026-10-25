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
        # the configuration and puts its lights back as they were (on or off,
        # brightness, color), even when the block raises.
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
        # @api public
        def stream
          config = Sdk.config
          key = config.client_key or raise AuthenticationError, 'client_key is not configured: pairing returns it'
          lights = snapshot
          update(action: 'start')
          started = true
          socket = DtlsSocket.open(host: config.host.to_s, identity: config.application_key.to_s, psk: [key].pack('H*'))
          yield Session.new(socket, id)
        ensure
          finish(socket, lights) if started
        end

        private

        # The bridge does not restore the lights when streaming stops: on
        # 2026-10-25 a lamp that was off stayed on, full red, the last frame.
        #
        # @return [Hash{String=>Hash}] per light id, the body that puts it back
        # @api private
        def snapshot
          ids = self['light_services'].map { it['rid'] }
          Sdk.Light.list.select { ids.include?(it.id) }.to_h { [it.id, restoration(it.data)] }
        end

        # @param light [Hash{String=>Object}] a light resource
        # @return [Hash{Symbol=>Hash}] update body restoring it
        # @api private
        def restoration(light)
          return { on: { on: false } } unless light.dig('on', 'on')

          state = { on: { on: true }, dimming: light['dimming']&.slice('brightness') }
          if light.dig('color_temperature', 'mirek_valid')
            state[:color_temperature] = light['color_temperature'].slice('mirek')
          else
            state[:color] = light['color']&.slice('xy')
          end
          state.compact
        end

        # Restores the lights after the stop: before it, the bridge would still
        # drive them from the stream.
        #
        # @param socket [DtlsSocket, nil]
        # @param lights [Hash{String=>Hash}] from {#snapshot}
        # @return [void]
        # @raise [ResponseError] the first light that could not be restored, once all were tried
        # @api private
        def finish(socket, lights)
          socket&.close
          update(action: 'stop')
          failures = lights.filter_map { |light, state| restore(light, state) }
          raise failures.first unless failures.empty?
        end

        # A lamp cut off at the wall answers 207: the lamps after it must still be restored.
        #
        # @param light [String] light id
        # @param state [Hash{Symbol=>Hash}] update body from {#restoration}
        # @return [ResponseError, nil] the failure, if any
        # @api private
        def restore(light, state)
          Sdk.Light(light).update(**state)
          nil
        rescue ResponseError => e
          e
        end
      end
    end
  end
end

Hue::Sdk::Models::EntertainmentConfiguration::Instance.include(Hue::Sdk::Entertainment::Streaming)
