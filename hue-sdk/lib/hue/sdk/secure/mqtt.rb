# frozen_string_literal: true

module Hue
  module Sdk
    module Secure
      # The few MQTT 3.1.1 packets {Follow} sends and reads.
      module Mqtt
        module_function

        # @param type [Integer] the first byte
        # @param body [String]
        # @return [String] the packet, its remaining length in 7-bit groups
        # @api private
        def packet(type, body)
          length = body.bytesize
          bytes = [] #: Array[Integer]
          loop do
            bytes << ((length & 0x7f) | (length > 0x7f ? 0x80 : 0))
            length >>= 7
            break if length.zero?
          end
          [type, *bytes].pack('C*') + body
        end

        # @param text [String]
        # @return [String] its length on two bytes, then its bytes
        # @api private
        def string(text) = [text.bytesize].pack('n') + text.b

        # @param socket [IO]
        # @return [Array(Integer, String)] the first byte and the body of a packet
        # @raise [EOFError] when the broker ends the connection
        # @api private
        def received(socket)
          type = socket.readbyte
          length = shift = 0
          loop do
            byte = socket.readbyte
            length |= (byte & 0x7f) << shift
            shift += 7
            break if byte < 0x80
          end
          [type, socket.read(length).to_s]
        end
      end
    end
  end
end
