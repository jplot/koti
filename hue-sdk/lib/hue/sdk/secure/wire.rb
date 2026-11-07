# frozen_string_literal: true

module Hue
  module Sdk
    module Secure
      # Reads protobuf 3 messages by field number. The app ships no +.proto+, and one message is read: a schema to
      # rewrite and compile would outweigh this reader.
      module Wire
        module_function

        # @param bytes [String] an encoded message
        # @return [Hash{Integer=>Array<Integer, String>}] the values of each field number, in order: an Integer for a
        #   varint, the raw bytes otherwise
        # @raise [Error] on a truncated message or a wire type protobuf 3 does not use
        # @api private
        def decode(bytes)
          fields = {} #: Hash[Integer, Array[Integer | String]]
          at = 0
          while at < bytes.bytesize
            key, at = varint(bytes, at)
            value, at = value(bytes, key & 7, at)
            (fields[key >> 3] ||= []) << value
          end
          fields
        end

        # @param fields [Hash{Integer=>Array<Integer, String>}] from {.decode}
        # @param tag [Integer]
        # @return [Array<String>] the values of a repeated string field
        # @api private
        def texts(fields, tag)
          fields[tag].to_a.filter_map { |value| value.dup.force_encoding(Encoding::UTF_8) if value.is_a?(String) }
        end

        # @param fields [Hash{Integer=>Array<Integer, String>}] from {.decode}
        # @param tag [Integer]
        # @return [String] the last value of a string field, empty when absent
        # @api private
        def text(fields, tag) = texts(fields, tag).last || ''

        # @param fields [Hash{Integer=>Array<Integer, String>}] from {.decode}
        # @param tag [Integer]
        # @return [Integer] the last value of a varint field, 0 when absent
        # @api private
        def number(fields, tag)
          value = fields[tag].to_a.last
          value.is_a?(Integer) ? value : 0
        end

        # @param bytes [String]
        # @param type [Integer] the wire type
        # @param at [Integer]
        # @return [Array(Integer, Integer), Array(String, Integer)] the value and where the next field starts
        # @raise [Error]
        # @api private
        def value(bytes, type, at)
          case type
          when 0 then varint(bytes, at)
          when 1 then slice(bytes, at, 8)
          when 2
            length, start = varint(bytes, at)
            slice(bytes, start, length)
          when 5 then slice(bytes, at, 4)
          else raise Error, "protobuf wire type #{type} is not read"
          end
        end

        # @param bytes [String]
        # @param at [Integer]
        # @return [Array(Integer, Integer)] the value and the index after it
        # @raise [Error]
        # @api private
        def varint(bytes, at)
          value = shift = 0
          loop do
            byte = bytes.getbyte(at) or raise Error, 'truncated protobuf message'
            value |= (byte & 0x7f) << shift
            shift += 7
            at += 1
            return [value, at] if byte < 0x80
          end
        end

        # @param bytes [String]
        # @param at [Integer]
        # @param length [Integer]
        # @return [Array(String, Integer)] the bytes and the index after them
        # @raise [Error]
        # @api private
        def slice(bytes, at, length)
          raise Error, 'truncated protobuf message' if at + length > bytes.bytesize

          [bytes.byteslice(at, length).to_s, at + length]
        end
      end
    end
  end
end
