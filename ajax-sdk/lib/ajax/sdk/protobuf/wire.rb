# frozen_string_literal: true

module Ajax
  module Sdk
    module Protobuf
      # Reads and writes the protobuf wire primitives: varints, zigzag integers and fixed-width fields.
      module Wire
        module_function

        # @param value [Integer] a non-negative integer, already in its unsigned 64-bit form
        # @return [String] its base-128 varint encoding
        def encode_varint(value)
          bytes = [] #: Array[Integer]
          while value > 0x7F
            bytes << ((value & 0x7F) | 0x80)
            value >>= 7
          end
          (bytes << value).pack('C*')
        end

        # @param data [String] the buffer
        # @param position [Integer] where the varint starts
        # @return [Array(Integer, Integer)] the value and the position just past it
        # @raise [DecodeError] when the varint runs past ten bytes or the buffer
        def read_varint(data, position)
          value = 0
          10.times do |index|
            byte = data.getbyte(position + index) or raise DecodeError, 'varint runs past the buffer'
            value |= (byte & 0x7F) << (7 * index)
            return [value, position + index + 1] if byte < 0x80
          end
          raise DecodeError, 'varint longer than ten bytes'
        end

        # @param value [Integer] a signed integer
        # @param bits [Integer] 32 or 64
        # @return [Integer] its zigzag encoding
        def zigzag_encode(value, bits) = ((value << 1) ^ (value >> (bits - 1))) & ((1 << bits) - 1)

        # @param value [Integer] a zigzag-encoded integer
        # @return [Integer] the signed integer it stands for
        def zigzag_decode(value) = (value >> 1) ^ -(value & 1)

        # @param value [Integer] a possibly negative integer
        # @param bits [Integer] 32 or 64
        # @return [Integer] its two's-complement value on that width
        def twos_complement(value, bits) = value & ((1 << bits) - 1)

        # @param value [Integer] an unsigned integer read from the wire
        # @param bits [Integer] 32 or 64
        # @return [Integer] the signed integer it stands for
        def from_twos_complement(value, bits)
          limit = 1 << (bits - 1)
          value >= limit ? value - (1 << bits) : value
        end
      end
    end
  end
end
