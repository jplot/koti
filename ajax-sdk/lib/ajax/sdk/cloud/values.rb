# frozen_string_literal: true

require_relative 'decode'

module Ajax
  module Sdk
    module Cloud
      # Reading and writing of the enum modules generated in +Messages+. Each holds +VALUES+, the short symbol
      # of every protobuf value, the default first.
      module Enum
        # @param value [Symbol, Integer, nil] a value as google-protobuf's +to_h+ gives it
        # @return [Symbol, Integer] its short symbol, the default for nil, or the number when the app 3.59 does
        #   not know it
        def from(value) = value.nil? ? default : values.fetch(value, value)

        # @param value [Symbol, Integer] a short symbol, or a number
        # @return [Symbol, Integer] the protobuf name google-protobuf takes, or the number as it is
        # @raise [ArgumentError] for a symbol the enum does not have
        def proto(value)
          return value if value.is_a?(Integer)

          values.key(value) || raise(ArgumentError, "#{name} has no value #{value.inspect}")
        end

        # @return [Symbol] the short symbol of the protobuf default
        def default = values.each_value.first #: Symbol

        private

        def values = const_get(:VALUES)
      end

      # Marks a generated response whose +success+ shares a oneof with +failure+ (or +error+), which it
      # gives as +problem+.
      module Outcome; end

      # Writers of the converted members of a generated value, back to what google-protobuf takes.
      #
      # @api private
      module Encode
        module_function

        # @param time [Time]
        # @return [Hash{Symbol=>Integer}] a +google.protobuf.Timestamp+
        def time(time) = { seconds: time.to_i, nanos: time.nsec }

        # A Duration gives its seconds and nanos the same sign: -1.5 s is -1 s and -500,000,000 ns.
        #
        # @param seconds [Float]
        # @return [Hash{Symbol=>Integer}] a +google.protobuf.Duration+
        def duration(seconds)
          whole = seconds.truncate
          { seconds: whole, nanos: ((seconds - whole) * 1_000_000_000).round }
        end

        # @param value [Object] what a wrapper such as +google.protobuf.StringValue+ holds
        # @return [Hash{Symbol=>Object}] the wrapper
        def wrapper(value) = { value: }
      end
    end
  end
end
