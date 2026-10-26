# frozen_string_literal: true

module Ajax
  module Sdk
    module Protobuf
      # Decodes a serialized message into a Hash keyed by field name (Symbol): only fields
      # present on the wire appear, repeated fields become Arrays, maps become Hashes, enums
      # become their value name (or the integer when unknown) and nested messages nest.
      class Decoder
        # Fixed-width types mapped to their Array#pack directive.
        FIXED = { 1 => 'E', 2 => 'e', 6 => 'Q<', 7 => 'V', 15 => 'l<', 16 => 'q<' }.freeze

        # Element wire type of a packed scalar (0 varint, 1 fixed64, 5 fixed32).
        PACKED_WIRE = Hash.new(0).merge!(1 => 1, 6 => 1, 16 => 1, 2 => 5, 7 => 5, 15 => 5).freeze

        # @param registry [Registry]
        # @api private
        def initialize(registry)
          @registry = registry
        end

        # @param full_name [String]
        # @param bytes [String]
        # @return [Hash{Symbol=>Object}]
        # @raise [DecodeError] on a malformed buffer
        def decode(full_name, bytes)
          by_number = @registry.message(full_name).fields.to_h { |field| [field.number, field] }
          result = {} #: Hash[Symbol, untyped]
          position = 0
          while position < bytes.bytesize
            tag, position = Wire.read_varint(bytes, position)
            position = read(by_number[tag >> 3], tag & 0x07, bytes, position, result)
          end
          result
        end

        private

        def read(field, wire, bytes, position, result)
          return skip(wire, bytes, position) unless field
          return read_packed(field, bytes, position, result) if field.label == 3 && wire == 2 && field.packed

          value, position = read_single(field, wire, bytes, position)
          store(field, value, result)
          position
        end

        def store(field, value, result)
          if map_entry?(field)
            entries = result[field.name] ||= {} #: Hash[untyped, untyped]
            entries[value[:key]] = value[:value]
          elsif field.label == 3
            (result[field.name] ||= []) << value
          else
            result[field.name] = value
          end
        end

        def read_packed(field, bytes, position, result)
          length, position = Wire.read_varint(bytes, position)
          stop = position + length
          raise DecodeError, 'packed field runs past the buffer' if stop > bytes.bytesize

          values = result[field.name] ||= []
          while position < stop
            value, position = read_single(field, PACKED_WIRE[field.type], bytes, position)
            values << value
          end
          position
        end

        def read_single(field, wire, bytes, position)
          case wire
          when 0 then read_varint_value(field, bytes, position)
          when 1 then read_fixed(field, bytes, position, 8)
          when 2 then read_length_delimited(field, bytes, position)
          when 5 then read_fixed(field, bytes, position, 4)
          else raise DecodeError, "wire type #{wire} (groups) is not supported"
          end
        end

        def read_varint_value(field, bytes, position)
          raw, position = Wire.read_varint(bytes, position)
          value = decode_varint(field.type, raw)
          [field.type == 14 ? enum_name(field, value) : value, position]
        end

        def decode_varint(type, raw)
          case type
          when 3, 5, 14 then Wire.from_twos_complement(raw, 64)
          when 8 then raw != 0
          when 17 then Wire.zigzag_decode(raw & 0xFFFFFFFF)
          when 18 then Wire.zigzag_decode(raw)
          else raw
          end
        end

        def read_fixed(field, bytes, position, width)
          stop = position + width
          raise DecodeError, 'fixed field runs past the buffer' if stop > bytes.bytesize

          format = FIXED.fetch(field.type) { raise DecodeError, "type #{field.type} is not fixed-width" }
          [(bytes.byteslice(position, width) || '').unpack1(format), stop]
        end

        def read_length_delimited(field, bytes, position)
          length, position = Wire.read_varint(bytes, position)
          stop = position + length
          raise DecodeError, 'length-delimited field runs past the buffer' if stop > bytes.bytesize

          [decode_bytes(field, bytes.byteslice(position, length) || ''), stop]
        end

        def decode_bytes(field, chunk)
          case field.type
          when 9 then chunk.dup.force_encoding(Encoding::UTF_8)
          when 11 then decode(ref(field), chunk)
          else chunk
          end
        end

        def skip(wire, bytes, position)
          case wire
          when 0 then Wire.read_varint(bytes, position).last
          when 1 then position + 8
          when 5 then position + 4
          when 2 then skip_delimited(bytes, position)
          else raise DecodeError, "wire type #{wire} (groups) is not supported"
          end
        end

        def skip_delimited(bytes, position) = Wire.read_varint(bytes, position).then { |length, after| after + length }
        def map_entry?(field) = field.type == 11 && field.label == 3 && @registry.message(ref(field)).map_entry
        def enum_name(field, number) = @registry.enum(ref(field)).values.fetch(number, number)
        def ref(field) = field.type_name || raise(DecodeError, "field #{field.name} lacks a type name")
      end

      # Encodes a Hash of field names to values into a serialized message.
      class Encoder
        # Field type to its wire type (0 varint, 1 fixed64, 2 length-delimited, 5 fixed32).
        WIRE = Hash.new(0).merge!(1 => 1, 6 => 1, 16 => 1, 2 => 5, 7 => 5, 15 => 5, 9 => 2, 11 => 2, 12 => 2).freeze

        # Fixed-width types mapped to their Array#pack directive.
        FIXED = Decoder::FIXED

        # @param registry [Registry]
        # @api private
        def initialize(registry)
          @registry = registry
        end

        # @param full_name [String]
        # @param hash [Hash{Symbol=>Object}]
        # @return [String]
        # @raise [ArgumentError] when a key is not a field of the message
        def encode(full_name, hash)
          by_name = @registry.message(full_name).fields.to_h { |field| [field.name, field] }
          hash.each_with_object(+''.b) do |(name, value), buffer|
            field = by_name[name] or raise ArgumentError, "#{full_name} has no field #{name}"
            encode_field(field, value, buffer)
          end
        end

        private

        def encode_field(field, value, buffer)
          return encode_map(field, value, buffer) if map_entry?(field)
          return encode_packed(field, value, buffer) if field.label == 3 && field.packed
          return value.each { |item| encode_value(field, item, buffer) } if field.label == 3

          encode_value(field, value, buffer)
        end

        def encode_map(field, value, buffer)
          value.each { |key, item| buffer << tag(field, 2) << delimited(encode(ref(field), key:, value: item)) }
        end

        def encode_packed(field, value, buffer)
          packed = value.each_with_object(+''.b) { |item, inner| inner << scalar(field, item) }
          buffer << tag(field, 2) << delimited(packed)
        end

        def encode_value(field, value, buffer)
          wire = WIRE[field.type]
          buffer << tag(field, wire) << (wire == 2 ? delimited(delimited_body(field, value)) : scalar(field, value))
        end

        def delimited_body(field, value) = field.type == 11 ? encode(ref(field), value) : value.b

        def scalar(field, value)
          format = FIXED[field.type]
          format ? [value].pack(format) : Wire.encode_varint(varint_value(field, value))
        end

        def varint_value(field, value)
          case field.type
          when 8 then value ? 1 : 0
          when 17 then Wire.zigzag_encode(value, 32)
          when 18 then Wire.zigzag_encode(value, 64)
          when 14 then Wire.twos_complement(enum_number(field, value), 64)
          else Wire.twos_complement(value, 64)
          end
        end

        def tag(field, wire) = Wire.encode_varint((field.number << 3) | wire)
        def delimited(bytes) = Wire.encode_varint(bytes.bytesize) + bytes
        def map_entry?(field) = field.type == 11 && field.label == 3 && @registry.message(ref(field)).map_entry
        def ref(field) = field.type_name || raise(ArgumentError, "field #{field.name} lacks a type name")

        def enum_number(field, value)
          return value if value.is_a?(Integer)

          @registry.enum(ref(field)).values.key(value) or raise ArgumentError, "unknown enum value #{value}"
        end
      end

      # Encodes and decodes protobuf messages against a {Registry} of schemas.
      class Codec
        # @param registry [Registry] the schemas to resolve message and enum names against
        # @api public
        def initialize(registry)
          @decoder = Decoder.new(registry)
          @encoder = Encoder.new(registry)
        end

        # @param full_name [String] fully qualified name of the message to decode
        # @param bytes [String] the serialized message
        # @return [Hash{Symbol=>Object}]
        # @raise [DecodeError] on a malformed buffer
        # @api public
        def decode(full_name, bytes) = @decoder.decode(full_name, bytes)

        # @param full_name [String] fully qualified name of the message to encode
        # @param hash [Hash{Symbol=>Object}] the values to encode
        # @return [String] the serialized message
        # @raise [ArgumentError] when a key is not a field of the message
        # @api public
        def encode(full_name, hash) = @encoder.encode(full_name, hash)
      end
    end
  end
end
