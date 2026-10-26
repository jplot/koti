# frozen_string_literal: true

require_relative 'huffman'

module Ajax
  module Sdk
    module Http2
      # HPACK (RFC 7541) header compression: a decoder that reads a header block into name/value
      # pairs, and an encoder that writes them back as literals without indexing. Both keep the
      # static table of Appendix A; the decoder also keeps a dynamic table with eviction.
      #
      module Hpack
        # Appendix A, 1-indexed; entry 0 is a placeholder so a wire index maps straight to a row.
        STATIC = [
          ['', ''],
          [':authority', ''], [':method', 'GET'],
          [':method', 'POST'], [':path', '/'],
          [':path', '/index.html'], [':scheme', 'http'],
          [':scheme', 'https'], [':status', '200'],
          [':status', '204'], [':status', '206'],
          [':status', '304'], [':status', '400'],
          [':status', '404'], [':status', '500'],
          ['accept-charset', ''], ['accept-encoding', 'gzip, deflate'],
          ['accept-language', ''], ['accept-ranges', ''],
          ['accept', ''], ['access-control-allow-origin', ''],
          ['age', ''], ['allow', ''],
          ['authorization', ''], ['cache-control', ''],
          ['content-disposition', ''], ['content-encoding', ''],
          ['content-language', ''], ['content-length', ''],
          ['content-location', ''], ['content-range', ''],
          ['content-type', ''], ['cookie', ''],
          ['date', ''], ['etag', ''],
          ['expect', ''], ['expires', ''],
          ['from', ''], ['host', ''],
          ['if-match', ''], ['if-modified-since', ''],
          ['if-none-match', ''], ['if-range', ''],
          ['if-unmodified-since', ''], ['last-modified', ''],
          ['link', ''], ['location', ''],
          ['max-forwards', ''], ['proxy-authenticate', ''],
          ['proxy-authorization', ''], ['range', ''],
          ['referer', ''], ['refresh', ''],
          ['retry-after', ''], ['server', ''],
          ['set-cookie', ''], ['strict-transport-security', ''],
          ['transfer-encoding', ''], ['user-agent', ''],
          ['vary', ''], ['via', ''],
          ['www-authenticate', '']
        ].freeze

        # The number of entries in the static table (its highest valid index).
        STATIC_SIZE = STATIC.size - 1

        # Header name to its lowest static index, for encoding a name the static table already holds.
        STATIC_NAMES = (1...STATIC.size).reverse_each.to_h { |index| [STATIC.fetch(index).first, index] }

        # Reads an HPACK header block into name/value pairs, keeping a dynamic table across calls.
        class Decoder
          # @param max_size [Integer] the dynamic table's size limit, in bytes
          def initialize(max_size: 4096)
            @limit = max_size
            @max_size = max_size
            @table = [] #: Array[[String, String]]
            @size = 0
          end

          # @param bytes [String] one header block
          # @return [Array<Array(String, String)>] its name/value pairs, in order
          # @raise [CompressionError] on a bad index, integer or Huffman string
          def decode(bytes)
            headers = [] #: Array[[String, String]]
            position = 0
            position = read_field(bytes, position, headers) while position < bytes.bytesize
            headers
          end

          private

          def read_field(bytes, position, headers)
            lead = bytes.getbyte(position).to_i
            return indexed(bytes, position, headers) if lead.anybits?(0x80)
            return literal(bytes, position, headers, 6, index: true) if lead.anybits?(0x40)
            return size_update(bytes, position) if lead.anybits?(0x20)

            literal(bytes, position, headers, 4, index: false)
          end

          def indexed(bytes, position, headers)
            index, position = read_integer(bytes, position, 7)
            headers << lookup(index)
            position
          end

          def literal(bytes, position, headers, prefix, index:)
            name_index, position = read_integer(bytes, position, prefix)
            name, position = name_index.zero? ? read_string(bytes, position) : [lookup(name_index).first, position]
            value, position = read_string(bytes, position)
            add(name, value) if index
            headers << [name, value]
            position
          end

          def size_update(bytes, position)
            size, position = read_integer(bytes, position, 5)
            raise CompressionError, "table size #{size} over the limit #{@limit}" if size > @limit

            @max_size = size
            evict
            position
          end

          def read_integer(bytes, position, prefix) # rubocop:disable Metrics/MethodLength -- RFC 7541 prefixed integer
            mask = (1 << prefix) - 1
            value = bytes.getbyte(position).to_i & mask
            position += 1
            return [value, position] if value < mask

            shift = 0
            loop do
              byte = bytes.getbyte(position) or raise CompressionError, 'integer runs past the block'
              position += 1
              value += (byte & 0x7F) << shift
              shift += 7
              break if byte.nobits?(0x80)
            end
            [value, position]
          end

          def read_string(bytes, position)
            huffman = bytes.getbyte(position).to_i.anybits?(0x80)
            length, position = read_integer(bytes, position, 7)
            data = bytes.byteslice(position, length) || ''
            raise CompressionError, 'string runs past the block' if data.bytesize < length

            [huffman ? Huffman.decode(data) : data, position + length]
          end

          def lookup(index)
            raise CompressionError, 'index 0 is not a header' if index.zero?
            return STATIC.fetch(index) if index <= STATIC_SIZE

            @table[index - STATIC_SIZE - 1] or raise CompressionError, "index #{index} past the table"
          end

          def add(name, value)
            @table.unshift([name, value])
            @size += entry_size(name, value)
            evict
          end

          def evict
            while @size > @max_size
              name, value = @table.pop
              @size -= entry_size(name.to_s, value.to_s)
            end
          end

          def entry_size(name, value) = name.bytesize + value.bytesize + 32
        end

        # Writes name/value pairs as literals without indexing, no Huffman, names indexed when static.
        class Encoder
          # @param headers [Array<Array(String, String)>] the name/value pairs to encode
          # @return [String] the header block
          def encode(headers)
            headers.each_with_object(+''.b) do |(name, value), out|
              index = STATIC_NAMES[name]
              out << (index ? integer(index, 4, 0) : (integer(0, 4, 0) << string(name)))
              out << string(value)
            end
          end

          private

          def integer(value, prefix, flags)
            mask = (1 << prefix) - 1
            out = +''.b
            return out << (flags | value) if value < mask

            out << (flags | mask)
            value -= mask
            while value >= 0x80
              out << ((value & 0x7F) | 0x80)
              value >>= 7
            end
            out << value
          end

          def string(text)
            bytes = text.b
            integer(bytes.bytesize, 7, 0) << bytes
          end
        end
      end
    end
  end
end
