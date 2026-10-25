# frozen_string_literal: true

module Hue
  module Sdk
    # Entertainment streaming: the lights of an entertainment configuration
    # driven at up to 50 updates per second.
    module Entertainment
      # Builds the HueStream (version 2) messages sent to an entertainment
      # configuration.
      module Message
        COLOR_SPACES = { rgb: 0, xy: 1 }.freeze
        private_constant :COLOR_SPACES

        MAX_CHANNELS = 20
        private_constant :MAX_CHANNELS

        module_function

        # @param configuration_id [String] id of the entertainment configuration
        # @param sequence [Integer] message counter, wrapped at 256
        # @param channels [Hash{Integer=>Array<Float>}] per channel id, red, green and blue, or x, y and
        #   brightness, each in 0.0..1.0 (values outside are clamped)
        # @param color_space [Symbol] +:rgb+ or +:xy+
        # @return [String] the binary message
        # @raise [ArgumentError] for more than 20 channels, an id that is not 36 characters long or
        #   another color space
        # @api public
        def encode(configuration_id:, sequence:, channels:, color_space: :rgb)
          header(configuration_id, sequence, channels.size, color_space) +
            channels.map { |id, values| [id, *values.map { (it.clamp(0.0, 1.0) * 65_535).round }].pack('Cn3') }.join
        end

        # @param configuration_id [String]
        # @param sequence [Integer]
        # @param size [Integer] number of channels
        # @param color_space [Symbol]
        # @return [String]
        # @raise [ArgumentError]
        # @api private
        def header(configuration_id, sequence, size, color_space)
          raise ArgumentError, "a message carries at most #{MAX_CHANNELS} channels, not #{size}" if size > MAX_CHANNELS
          raise ArgumentError, 'configuration_id must be 36 characters long' if configuration_id.size != 36

          space = COLOR_SPACES.fetch(color_space) { raise ArgumentError, 'color_space must be :rgb or :xy' }
          ['HueStream', 2, 0, sequence % 256, 0, 0, space, 0, configuration_id].pack('a9C7a36')
        end
      end
    end
  end
end
