# frozen_string_literal: true

module Miele
  module Sdk
    # Typed values of the DOP2 and Dop1 objects the Miele app reads and writes, generated from its assemblies: a
    # module per family (+Oven+, +Hood+…) with a Data class per object and a module per enum, each loaded on its
    # first use.
    module Objects
      NUMERALS = %i[u8 i8 e8 u16 i16 e16 u32 i32 e32 u64 i64 e64].freeze
      # The wire types the app's GetEnum, GetGeneratedObject, GetEnums and GetGeneratedObjects accept: any other
      # fails that one attribute.
      WIRE_TYPES = { enum: NUMERALS, struct: [:struct], enum_array: NUMERALS.map { :"#{it}_array" },
                     struct_array: [:struct_array] }.freeze
      private_constant :NUMERALS, :WIRE_TYPES

      # Reading and writing of the generated enum modules. Each holds +VALUES+, the number of each short symbol.
      module Enum
        # Three enums give one number two names (+GLOBAL_SUBPPHASE_NONE+ and +…_SUPERIOR_LEVEL+): the first one reads.
        #
        # @param number [Integer]
        # @return [Symbol, Integer] its symbol, or the number when the app does not know it
        def from(number) = values.key(number) || number

        # @param value [Symbol, Integer]
        # @return [Integer]
        # @raise [ArgumentError] for a symbol the enum does not have
        def to_i(value)
          return value if value.is_a?(Integer)

          values.fetch(value) { raise ArgumentError, "#{name} has no value #{value.inspect}" }
        end

        private

        def values = const_get(:VALUES)
      end

      # Reading of a generated DOP2 class, whose +MEMBERS+ give the attribute index, the kind and the type of each
      # member.
      module Dop2Class
        # @param fields [Hash{Integer=>Dop2::Field}] the attributes of a leaf
        # @return [Data] nil for each attribute the leaf lacks
        def from(fields)
          values = layout.to_h do |member, (index, kind, type)|
            [member, fields[index]&.then { Objects.read(it, kind, type) }]
          end
          new(**values, raw: fields)
        end

        # Data's own +members+ lists the names only.
        #
        # @return [Hash{Symbol=>Array}]
        def layout = const_get(:MEMBERS)
      end

      # Writing back of a generated DOP2 value.
      module Dop2Value
        # The app writes only attributes it read: its setters raise on the others.
        #
        # @return [Hash{Integer=>Dop2::Field}] +raw+, with each member changed since the read in its wire type as read
        # @raise [ArgumentError] when a changed member was not read
        def to_fields
          read = self.class.from(raw)
          self.class.layout.each_with_object(raw.dup) do |(member, spec), fields|
            value = public_send(member)
            fields.store(*written(member, value, spec)) unless value == read.public_send(member)
          end
        end

        private

        # @return [Array(Integer, Dop2::Field)]
        def written(member, value, spec)
          index, kind, type = spec
          field = raw.fetch(index) { raise ArgumentError, "#{self.class.name}: #{member} was not read" }
          [index, Dop2::Field.new(type: field.type, value: Objects.write(value, kind, type))]
        end
      end

      # Reading of a generated Dop1 class. Its +MEMBERS+ give each member's kind and offset, then the size and enum
      # of a field, the bit count and enum of +:bits+, the length and class of a +:section+, or the count and width of
      # an +:array+.
      module Dop1Class
        # @param bytes [String] the object's bytes
        # @param endian [Symbol, nil] +:msb+ or +:lsb+: the object's own, else the one its reader gives
        # @return [Data] nil for each member the bytes do not reach
        def from(bytes, endian: const_get(:ENDIAN))
          new(**layout.to_h { |member, spec| [member, Dop1Bytes.read(bytes, endian, spec)] }, bytes:, endian:)
        end

        # Data's own +members+ lists the names only.
        #
        # @return [Hash{Symbol=>Array}]
        def layout = const_get(:MEMBERS)
      end

      # Writing back of a generated Dop1 value.
      module Dop1Value
        # @return [String] the bytes with each member changed since the read, or for a write section the pieces of
        #   them its +GenerateWriteBytes+ sends
        def to_bytes
          return changed_bytes unless self.class.const_defined?(:WRITE_BYTES, false)

          self.class.const_get(:WRITE_BYTES).map { |offset, length| changed_bytes.byteslice(offset, length) }.join
        end

        # @return [String] the bytes with each member changed since the read
        # @api private
        def changed_bytes
          read = self.class.from(bytes, endian:)
          self.class.layout.each_with_object(bytes.b) do |(member, spec), out|
            value = public_send(member)
            Dop1Bytes.write(out, endian, value, spec) unless value == read.public_send(member)
          end
        end
      end

      # The byte layouts of Dop1: integers in the object's endianness, and bit fields whose bit k is bit k mod 8 of
      # byte k div 8 once an MSB object's bytes are reversed.
      #
      # @api private
      module Dop1Bytes
        DIRECTIVES = { u8: 'C', s8: 'c', u16: 'S', s16: 's', u32: 'L', s32: 'l' }.freeze
        WIDTHS = { 1 => 'C', 2 => 'S', 4 => 'L', 8 => 'Q' }.freeze
        ORDERS = { msb: '>', lsb: '<' }.freeze
        private_constant :DIRECTIVES, :WIDTHS, :ORDERS

        module_function

        # @param spec [Array] a member of +MEMBERS+: kind, offset, extent and detail
        # @return [Object, nil]
        def read(bytes, endian, spec)
          kind, offset, extent, detail = spec
          case kind
          when :section then section(bytes, endian, offset, extent, detail)
          when :array then array(bytes, endian, offset, extent, detail)
          else field(bytes, endian, spec)&.then { enum(detail).from(it) }
          end
        end

        # @return [void]
        def write(out, endian, value, spec)
          kind, offset, extent, detail = spec
          case kind
          when :section then out.bytesplice(offset, extent, value.changed_bytes)
          when :array then put_array(out, endian, offset, value, detail)
          when :bits then put_bits(out, endian, offset, extent, enum(detail).to_i(value))
          else put(out, endian, DIRECTIVES.fetch(kind), offset, enum(detail).to_i(value))
          end
        end

        def section(bytes, endian, offset, length, klass)
          Objects.const_get(klass).from(bytes.byteslice(offset, length), endian:) if offset < bytes.bytesize
        end

        def field(bytes, endian, spec)
          kind, offset, extent = spec
          return bits(bytes, endian, offset, extent) if kind == :bits

          number(bytes, endian, DIRECTIVES.fetch(kind), offset, extent)
        end

        def array(bytes, endian, offset, count, width)
          Array.new(count) { number(bytes, endian, WIDTHS.fetch(width), offset + (it * width), width) }
        end

        def put_array(out, endian, offset, items, width)
          items.each_with_index { |item, index| put(out, endian, WIDTHS.fetch(width), offset + (index * width), item) }
        end

        # A field without enum reads and writes as its number.
        def enum(type) = type ? Objects.const_get(type) : Plain

        def number(bytes, endian, directive, offset, size)
          bytes.unpack1(directive(directive, endian), offset:) if offset + size <= bytes.bytesize #: Integer?
        end

        def put(out, endian, directive, offset, value)
          packed = [value].pack(directive(directive, endian))
          out.bytesplice(offset, packed.bytesize, packed)
        end

        def directive(directive, endian) = %w[C c].include?(directive) ? directive : directive + ORDERS.fetch(endian)

        def bits(bytes, endian, offset, count)
          (integer(bytes, endian) >> offset) & ((1 << count) - 1) if offset + count <= bytes.bytesize * 8
        end

        def put_bits(out, endian, offset, count, value)
          mask = ((1 << count) - 1) << offset
          out.replace(packed((integer(out, endian) & ~mask) | ((value << offset) & mask), out.bytesize, endian))
        end

        def packed(integer, size, endian)
          ordered = Array.new(size) { (integer >> (8 * it)) & 0xFF }
          (endian == :msb ? ordered.reverse : ordered).pack('C*')
        end

        def integer(bytes, endian)
          ordered = bytes.unpack('C*') #: Array[Integer]
          (endian == :msb ? ordered : ordered.reverse).reduce(0) { |sum, byte| (sum << 8) | byte }
        end

        # The enum of a field the app types as a number.
        module Plain
          module_function

          # @return [Integer] the number as it is
          def from(number) = number

          # @return [Integer] the value as it is
          def to_i(value) = value
        end
        private_constant :Plain
        private_class_method :section, :field, :array, :put_array, :enum, :number, :put, :directive, :bits, :put_bits,
                             :packed, :integer
      end

      # @param field [Dop2::Field] an attribute as {Dop2} decodes it
      # @param kind [Symbol] the kind of its member in +MEMBERS+
      # @param type [String, nil] the member's enum or class, below Objects
      # @return [Object, nil] the member's value, nil when the wire type does not fit the kind
      # @api private
      def self.read(field, kind, type)
        return if WIRE_TYPES.key?(kind) && !WIRE_TYPES.fetch(kind).include?(field.type)

        case kind
        when :enum, :struct then const_get(type).from(field.value)
        when :enum_array, :struct_array then field.value.map { const_get(type).from(it) }
        else field.value
        end
      end

      # @param value [Object] a member's value
      # @param kind [Symbol] its kind in +MEMBERS+
      # @param type [String, nil] its enum or class, below Objects
      # @return [Object] the value {Dop2} encodes
      # @api private
      def self.write(value, kind, type)
        case kind
        when :enum then const_get(type).to_i(value)
        when :enum_array then value.map { const_get(type).to_i(it) }
        when :struct then value.to_fields
        when :struct_array then value.map(&:to_fields)
        else value
        end
      end
    end
  end
end

require_relative 'objects/families'
