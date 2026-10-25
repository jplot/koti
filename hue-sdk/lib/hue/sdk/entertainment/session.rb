# frozen_string_literal: true

module Hue
  module Sdk
    module Entertainment
      # Sends frames to the lights of a started entertainment configuration.
      class Session
        # @param socket [DtlsSocket] open socket to the bridge
        # @param configuration_id [String] id of the entertainment configuration
        # @api private
        def initialize(socket, configuration_id)
          @socket = socket
          @configuration_id = configuration_id
          @sequence = 0
        end

        # Sends one frame; send them at up to 50 per second.
        #
        # @param channels [Hash{Integer=>Array<Float>}] per channel id, three values in 0.0..1.0
        #   (see {Message.encode})
        # @param color_space [Symbol] +:rgb+ or +:xy+ (x, y and brightness)
        # @return [void]
        # @raise [ArgumentError] for more than 20 channels
        # @raise [ConnectionError] if the write fails
        # @api public
        def write(channels, color_space: :rgb)
          message = Message.encode(configuration_id: @configuration_id, sequence: @sequence, channels:, color_space:)
          @socket.write(message)
          @sequence += 1
        end
      end
    end
  end
end
