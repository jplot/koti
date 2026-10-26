# frozen_string_literal: true

module Ajax
  module Sdk
    module Http2
      # RFC 7540 frame type codes and the flag bits this client reads or writes.
      module Frames
        DATA = 0
        HEADERS = 1
        RST_STREAM = 3
        SETTINGS = 4
        PING = 6
        GOAWAY = 7
        WINDOW_UPDATE = 8
        CONTINUATION = 9

        END_STREAM = 0x1
        ACK = 0x1
        END_HEADERS = 0x4

        private_constant :DATA, :HEADERS, :RST_STREAM, :SETTINGS, :PING, :GOAWAY, :WINDOW_UPDATE,
                         :CONTINUATION, :END_STREAM, :ACK, :END_HEADERS
      end

      # One HTTP/2 frame: a 9-byte header (24-bit length, 8-bit type, 8-bit flags, 31-bit stream id)
      # followed by its payload.
      Frame = Data.define(:type, :flags, :stream_id, :payload)

      # Reopened so Steep resolves the readers inside these methods.
      class Frame
        # @param io [IO] a stream positioned at a frame header
        # @return [Frame]
        # @raise [EOFError] when the stream ends inside the frame
        def self.read(io) # rubocop:disable Metrics/AbcSize -- fixed 9-byte frame header parse
          header = io.read(9)
          raise EOFError, 'stream ended before a frame header' if header.nil? || header.bytesize < 9

          high, low, type, flags, stream_id = header.unpack('CnCCN')
          length = (high << 16) | low
          payload = length.zero? ? ''.b : io.read(length)
          raise EOFError, 'stream ended inside a frame payload' if payload.nil? || payload.bytesize < length

          new(type:, flags:, stream_id: stream_id & 0x7FFFFFFF, payload:)
        end

        # @return [Boolean] whether +flag+ (a Frames bit) is set
        def flag?(flag) = flags.anybits?(flag)

        # @return [String] the frame on the wire, header and payload
        def to_s
          length = payload.bytesize
          [length >> 16, length & 0xFFFF, type, flags, stream_id].pack('CnCCN') + payload
        end
      end
    end
  end
end
