# frozen_string_literal: true

require_relative 'model'
require_relative 'index'

module Schema
  module Generate
    # Writes the Ruby of one object outside another: a Data class per DOP2 or Dop1 object, a module per enum. The
    # support modules (Dop2Class, Enum…) come from lib/miele/sdk/objects.rb.
    module Ruby
      HEADER = "# frozen_string_literal: true\n\n#{Index::HEADER}".freeze
      SCALARS = { 1 => 'Boolean', 14 => 'Float', 15 => 'Float', 17 => 'Array<Boolean>', 30 => 'Array<Float>',
                  31 => 'Array<Float>', 32 => 'String' }.freeze
      ADDRESSES = ['# Where the app reads or writes it: [unit, attribute] when it sends no index, else [unit,',
                   '# attribute, idx1, idx2], nil for an index it computes.'].freeze

      module_function

      # @return [String]
      def file(model, item)
        lines = Index.wrap(["module #{Naming.constant(item.family)}", *Index.indent(type(model, item)), 'end'])
        [HEADER, *lines, ''].join("\n")
      end

      def type(model, item)
        case item
        when Enum then enum(item)
        when Dop2Class then dop2(item)
        else dop1(model, item)
        end
      end

      def define(item, members) = "#{Index.short(item)} = ::Data.define(#{members.map(&:inspect).join(', ')})"

      def origin(item, what) = "# +#{item.name}+, #{what} of the app's +#{item.family}+ module."

      def attribute(member, type, where) = ["# @!attribute [r] #{member}", "#   @return [#{type}] #{where}"]

      def frozen(values) = "[#{values.map { "#{it.inspect}.freeze" }.join(', ')}].freeze"

      def table(name, rows) = ["#{name} = {", *rows.map { "  #{it}," }, '}.freeze']

      def enum(enum)
        values = enum.values.map { |symbol, number| "#{symbol.inspect} => #{number}" }
        [origin(enum, 'an enum'), "module #{Index.short(enum)}", '  extend Enum', '',
         '  # The number of each short symbol, as the app declares them.', *Index.indent(table('VALUES', values)),
         'end']
      end

      def dop2(klass)
        doc = klass.fields.flat_map { attribute(it.member, "#{yard(it)}, nil", "attribute #{it.index}") }
        [origin(klass, 'a DOP2 object'), '#', *doc,
         *attribute(:raw, 'Hash{Integer=>Dop2::Field}', 'the attributes as read'),
         define(klass, [*klass.fields.map(&:member), :raw]), '', "class #{Index.short(klass)}",
         *Index.indent(dop2_body(klass)), 'end']
      end

      def dop2_body(klass)
        members = klass.fields.map { "#{it.member}: #{[it.index, it.kind, it.type].inspect}.freeze" }
        ['extend Dop2Class', 'include Dop2Value', '', *ADDRESSES, "ADDRESSES = #{frozen(klass.addresses)}", '',
         '# The attribute index, the kind and the type of each member.', *table('MEMBERS', members)]
      end

      def yard(field)
        type = field.type&.then { "Objects::#{it}" }
        case field.kind
        when :enum then 'Symbol, Integer'
        when :enum_array then 'Array<Symbol, Integer>'
        when :struct then type
        when :struct_array then "Array<#{type}>"
        when :array then SCALARS.fetch(field.wire, 'Array<Integer>')
        else SCALARS.fetch(field.wire, 'Integer')
        end
      end

      def dop1(model, klass)
        parts = [*klass.fields, *klass.sections, *klass.arrays]
        [*dop1_doc(klass, parts), define(klass, [*parts.map(&:member), :bytes, :endian]), '',
         "class #{Index.short(klass)}", *Index.indent(dop1_body(model, klass, parts)), 'end']
      end

      def dop1_doc(klass, parts)
        [origin(klass, klass.id ? "Dop1 object #{klass.id}" : 'a part of a Dop1 object'), '#',
         *parts.flat_map { attribute(it.member, "#{dop1_yard(it)}, nil", where(it)) },
         *attribute(:bytes, 'String', 'the bytes as read'), *attribute(:endian, 'Symbol, nil', '+:msb+ or +:lsb+')]
      end

      def dop1_yard(part)
        case part
        in Dop1Part[count: Integer] then 'Array<Integer>'
        in Dop1Part then "Objects::#{part.type}"
        else part.type ? 'Symbol, Integer' : 'Integer'
        end
      end

      def where(part)
        case part
        in Dop1Part[count: Integer] then "#{part.count} × #{part.width} bytes at #{part.offset}"
        in Dop1Part then "bytes #{part.offset}, #{part.length} long"
        in { kind: :bits } then "bits #{part.offset}, #{part.length} long"
        else "#{part.kind} at byte #{part.offset}"
        end
      end

      def dop1_body(model, klass, parts)
        members = parts.map { "#{it.member}: #{spec(it)}.freeze" }
        ['extend Dop1Class', 'include Dop1Value', '', *dop1_constants(klass), '',
         '# The kind, offset and layout of each member.', *table('MEMBERS', members),
         *Index.children(model, klass).flat_map { ['', *dop1(model, it)] }]
      end

      def dop1_constants(klass)
        id = ["# The object's id in a Dop1 request.", "ID = #{klass.id.inspect}", ''] if klass.id
        if klass.write
          pieces = ['', "# The pieces of its bytes the app's GenerateWriteBytes sends: offset and length.",
                    "WRITE_BYTES = #{frozen(klass.write_bytes)}", '', '# Its length, to build it empty.',
                    "LENGTH = #{klass.length}"]
        end
        endian = ['# Its byte order, nil when its reader gives it.', "ENDIAN = #{klass.endian.inspect}"]
        [*id, *endian, *pieces]
      end

      def spec(part)
        case part
        in Dop1Part[count: Integer] then [:array, part.offset, part.count, part.width]
        in Dop1Part then [:section, part.offset, part.length, part.type]
        else [part.kind, part.offset, part.size || part.length, part.type]
        end.inspect
      end
    end
  end
end
