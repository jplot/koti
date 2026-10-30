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
      #   @return [Symbol] a scalar (+:bool+, +:u8+ to +:e64+, +:float+, +:double+), +:struct+, the array of a
      #     scalar (+:u16_array+…), +:string+ or +:struct_array+
      # @!attribute [r] value
      #   @return [Integer, Float, Boolean, String, Array<Integer, Float, Boolean>, Hash{Integer=>Field},
      #     Array<Hash{Integer=>Field}>]
      Field = Data.define(:type, :value)

      SCALARS = {
        bool: ['C', 1], u8: ['C', 1], i8: ['c', 1], e8: ['C', 1], u16: ['n', 2], i16: ['s>', 2], e16: ['n', 2],
        u32: ['N', 4], i32: ['l>', 4], e32: ['N', 4], u64: ['Q>', 8], i64: ['q>', 8], e64: ['Q>', 8],
        float: ['g', 4], double: ['G', 8]
      }.freeze
      private_constant :SCALARS

      # The type codes of the app's Dop2AttributeFactory, 1 to 33.
      TYPES = [*SCALARS.keys, :struct, *SCALARS.keys.map { :"#{it}_array" }, :string, :struct_array]
              .each.with_index(1).to_h { |type, code| [code, type] }.freeze
      private_constant :TYPES

      CODES = TYPES.invert.freeze
      private_constant :CODES

      # Walks the bytes of one leaf.
      class Reader
        # @param bytes [String]
        def initialize(bytes)
          @bytes = bytes.b
          @offset = 0
          @end = @bytes.bytesize
        end

        # Bodies come padded with spaces: the leaf ends at its declared length.
        #
        # @return [Leaf]
        # @raise [DecodeError]
        def leaf
          @end = [2 + read('n', 2), @end].min
          unit, attribute, idx1, idx2, count = Array.new(5) { read('n', 2) }
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
          type = TYPES.fetch(code) do
            raise DecodeError, format('unknown DOP2 type 0x%<code>02x at byte %<position>d', code:, position:)
          end
          Field.new(type:, value: value(type))
        end

        # @param type [Symbol]
        # @return [Object]
        def value(type)
          return scalar(type) if SCALARS.key?(type)

          count = read('n', 2)
          case type
          when :struct then fields(count)
          when :string then read("a#{count}", count).sub(/\0+\z/, '').force_encoding(Encoding::UTF_8)
          when :struct_array then Array.new(count) { fields(read('n', 2)) }
          else Array.new(count) { scalar(Dop2.element(type)) }
          end
        end

        # @param type [Symbol] one of {SCALARS}
        # @return [Integer, Float, Boolean]
        def scalar(type)
          directive, size = SCALARS.fetch(type)
          value = read(directive, size)
          type == :bool ? value == 1 : value
        end

        # @return [Object]
        # @raise [DecodeError] if the leaf ends before the value
        def read(directive, size)
          raise DecodeError, "DOP2 leaf truncated at byte #{@offset}" if @offset + size > @end

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

      # @param leaf [Leaf]
      # @return [String] the leaf's bytes, unpadded
      # @raise [ArgumentError] if a value does not fit its field, or a type is unknown
      # @api public
      def encode(leaf)
        header = [leaf.unit, leaf.attribute, leaf.idx1, leaf.idx2, leaf.fields.size].pack('n5')
        body = header + encode_fields(leaf.fields)
        [body.bytesize].pack('n') + body
      end

      # @param fields [Hash{Integer=>Field}]
      # @return [String]
      # @api private
      def encode_fields(fields)
        fields.map do |index, field|
          code = CODES.fetch(field.type) { raise ArgumentError, "unknown DOP2 type #{field.type.inspect}" }
          [index, code].pack('nC') + payload(field.type, field.value)
        end.join
      end

      # The app counts the NUL it appends to a string in the string's length.
      #
      # @param type [Symbol]
      # @param value [Object]
      # @return [String]
      # @api private
      def payload(type, value)
        return scalar_bytes(type, value) if SCALARS.key?(type)

        case type
        when :struct then struct_bytes(value)
        when :string then "#{value}\0".b.then { [it.bytesize].pack('n') + it }
        when :struct_array then sequence(value) { struct_bytes(it) }
        else sequence(value) { scalar_bytes(element(type), it) }
        end
      end

      # @param fields [Hash{Integer=>Field}]
      # @return [String] the count, then the fields
      # @api private
      def struct_bytes(fields) = [fields.size].pack('n') + encode_fields(fields)

      # @param items [Array]
      # @yieldparam item [Object]
      # @yieldreturn [String] the bytes of one item
      # @return [String] the count, then the items
      # @api private
      def sequence(items, &) = [items.size].pack('n') + items.map(&).join

      # @param type [Symbol] an array type
      # @return [Symbol] the type of its elements
      # @api private
      def element(type) = type.to_s.delete_suffix('_array').to_sym

      # @param type [Symbol] one of {SCALARS}
      # @param value [Integer, Float, Boolean]
      # @return [String]
      # @api private
      def scalar_bytes(type, value)
        directive, size = SCALARS.fetch(type)
        [scalar_value(type, value, size)].pack(directive)
      end

      # @param type [Symbol]
      # @param value [Integer, Float, Boolean]
      # @param size [Integer] bytes of the value
      # @return [Integer, Float]
      # @raise [ArgumentError] if the value does not fit the field
      # @api private
      def scalar_value(type, value, size)
        return value ? 1 : 0 if type == :bool
        return value if %i[float double].include?(type)
        raise ArgumentError, "#{value} does not fit a #{type} field" unless range(type, size).cover?(value)

        value
      end

      # @param type [Symbol] +:i8+ to +:i64+ are signed
      # @param size [Integer] bytes
      # @return [Range<Integer>] values a scalar of that type holds
      # @api private
      def range(type, size)
        bits = size * 8
        type.start_with?('i') ? (-(1 << (bits - 1))...(1 << (bits - 1))) : (0...(1 << bits))
      end
    end
  end
end
