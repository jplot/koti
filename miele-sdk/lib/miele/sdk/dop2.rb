# frozen_string_literal: true

module Miele
  module Sdk
    # Binary leaves of the DOP2 protocol, read and written at
    # +/Devices/{fab}/DOP2/{unit}/{attribute}+.
    module Dop2
      # A leaf that does not follow the DOP2 encoding.
      class DecodeError < Error; end

      # One DOP2 leaf.
      #
      # @!attribute [r] unit
      #   @return [Integer]
      # @!attribute [r] attribute
      #   @return [Integer]
      # @!attribute [r] idx1
      #   @return [Integer] index of the leaf in a list, 0 for a single leaf
      # @!attribute [r] idx2
      #   @return [Integer]
      # @!attribute [r] fields
      #   @return [Hash{Integer=>Field}] fields by index
      Leaf = Data.define(:unit, :attribute, :idx1, :idx2, :fields)

      # One field of a leaf.
      #
      # @!attribute [r] type
      #   @return [Symbol] +:bool+, +:u8+ to +:e64+, +:struct+, +:e16_array+, +:string+ or +:struct_array+
      # @!attribute [r] value
      #   @return [Integer, Boolean, String, Array<Integer>, Hash{Integer=>Field}, Array<Hash{Integer=>Field}>]
      Field = Data.define(:type, :value)

      SCALARS = {
        0x01 => [:bool, 'C', 1], 0x02 => [:u8, 'C', 1], 0x03 => [:i8, 'c', 1], 0x04 => [:e8, 'C', 1],
        0x05 => [:u16, 'n', 2], 0x06 => [:i16, 's>', 2], 0x07 => [:e16, 'n', 2],
        0x08 => [:u32, 'N', 4], 0x09 => [:i32, 'l>', 4], 0x0a => [:e32, 'N', 4],
        0x0b => [:u64, 'Q>', 8], 0x0c => [:i64, 'q>', 8], 0x0d => [:e64, 'Q>', 8]
      }.freeze
      private_constant :SCALARS

      COMPOSITES = { 0x10 => :struct, 0x17 => :e16_array, 0x20 => :string, 0x21 => :struct_array }.freeze
      private_constant :COMPOSITES

      # Walks the bytes of one leaf.
      class Reader
        # @param bytes [String]
        def initialize(bytes)
          @bytes = bytes.b
          @offset = 0
        end

        # @return [Leaf]
        # @raise [DecodeError]
        def leaf
          _length, unit, attribute, idx1, idx2, count = Array.new(6) { read('n', 2) }
          Leaf.new(unit:, attribute:, idx1:, idx2:, fields: fields(count))
        end

        private

        # @param count [Integer]
        # @return [Hash{Integer=>Field}]
        def fields(count) = Array.new(count) { [read('n', 2), field] }.to_h

        # @return [Field]
        def field
          position = @offset
          code = read('C', 1)
          return scalar(code) if SCALARS.key?(code)

          type = COMPOSITES.fetch(code) do
            raise DecodeError, format('unknown DOP2 type 0x%<code>02x at byte %<position>d', code:, position:)
          end
          Field.new(type:, value: composite(type))
        end

        # @param code [Integer] one of {SCALARS}
        # @return [Field]
        def scalar(code)
          type, directive, size = SCALARS.fetch(code)
          value = read(directive, size)
          Field.new(type:, value: type == :bool ? value == 1 : value)
        end

        # @param type [Symbol]
        # @return [Object]
        def composite(type)
          count = read('n', 2)
          case type
          when :struct then fields(count)
          when :e16_array then Array.new(count) { read('n', 2) }
          when :string then read("a#{count}", count).force_encoding(Encoding::UTF_8)
          else Array.new(count) { fields(read('n', 2)) }
          end
        end

        # @return [Object]
        # @raise [DecodeError] if the leaf ends before the value
        def read(directive, size)
          raise DecodeError, "DOP2 leaf truncated at byte #{@offset}" if @offset + size > @bytes.bytesize

          @bytes.unpack1(directive, offset: @offset).tap { @offset += size }
        end
      end
      private_constant :Reader

      module_function

      # @param bytes [String] a leaf as the appliance serves it, padding included
      # @return [Leaf]
      # @raise [DecodeError] on an unknown type or a truncated leaf
      # @api public
      def decode(bytes) = Reader.new(bytes).leaf

      # @param leaf [Leaf] a leaf of scalar fields
      # @return [String] the leaf's bytes, unpadded
      # @raise [ArgumentError] if a field is a struct, an array or a string
      # @api public
      def encode(leaf)
        body = [leaf.unit, leaf.attribute, leaf.idx1, leaf.idx2, leaf.fields.size].pack('n5') +
               leaf.fields.map { |index, field| encode_field(index, field) }.join
        [body.bytesize].pack('n') + body
      end

      # @param index [Integer]
      # @param field [Field]
      # @return [String]
      # @api private
      def encode_field(index, field)
        code, (_, directive) = SCALARS.find { |_, (type)| type == field.type }
        raise ArgumentError, "cannot encode a #{field.type} field" unless code

        value = field.value
        value = value ? 1 : 0 if field.type == :bool
        [index, code, value].pack("nC#{directive}")
      end
    end
  end
end
