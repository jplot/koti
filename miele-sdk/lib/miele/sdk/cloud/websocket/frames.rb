# frozen_string_literal: true

require 'securerandom'

module Miele
  module Sdk
    module Cloud
      class Websocket
        # RFC 6455 frames: the client masks what it sends, the server does not.
        module Frames
          CONTINUATION = 0
          TEXT = 1
          BINARY = 2
          CLOSE = 8
          PING = 9
          PONG = 10
          private_constant :CONTINUATION, :TEXT, :BINARY, :CLOSE, :PING, :PONG

          private

          # @param socket [IO]
          # @return [Array(Integer, String)] the opcode and the payload
          # @raise [EOFError] when the cloud closes the connection
          def read_frame(socket)
            first, second = exactly(socket, 2).bytes
            size = extended(socket, second.to_i & 0x7F)
            mask = second.to_i.anybits?(0x80) ? exactly(socket, 4).bytes : nil
            payload = exactly(socket, size)
            [first.to_i & 0x0F, mask ? unmask(payload, mask) : payload]
          end

          # @param socket [IO]
          # @param size [Integer] the 7-bit length: 126 and 127 announce 2 and 8 more bytes, big-endian
          # @return [Integer]
          def extended(socket, size)
            return size if size < 126

            exactly(socket, size == 126 ? 2 : 8).bytes.inject(0) { |sum, byte| (sum << 8) | byte }
          end

          # @param socket [IO]
          # @param opcode [Integer]
          # @param payload [String]
          # @return [void]
          def write_frame(socket, opcode, payload)
            payload = payload.b
            mask = SecureRandom.random_bytes(4)
            socket.write([0x80 | opcode].pack('C') + length(payload.bytesize) + mask + unmask(payload, mask.bytes))
          end

          # @param size [Integer]
          # @return [String] the masked length field
          def length(size)
            return [0x80 | size].pack('C') if size < 126
            return [0xFE, size].pack('Cn') if size < 65_536

            [0xFF, size].pack('CQ>')
          end

          # @param payload [String]
          # @param mask [Array<Integer>]
          # @return [String]
          def unmask(payload, mask)
            payload.bytes.each_with_index.map { |byte, index| byte ^ mask[index % 4] }.pack('C*')
          end

          # @param socket [IO]
          # @param count [Integer]
          # @return [String]
          # @raise [EOFError]
          def exactly(socket, count)
            bytes = socket.read(count)
            raise EOFError, 'the cloud websocket closed' if bytes.nil? || bytes.bytesize < count

            bytes
          end
        end
      end
    end
  end
end
