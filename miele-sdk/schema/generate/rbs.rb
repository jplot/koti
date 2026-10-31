# frozen_string_literal: true

require_relative 'model'
require_relative 'index'

module Schema
  module Generate
    # Writes the RBS of one object outside another, every member nilable and every type named from +::+.
    module Rbs
      OBJECTS = '::Miele::Sdk::Objects'
      FIELDS = '::Hash[::Integer, ::Miele::Sdk::Dop2::Field]'
      SCALARS = { 1 => 'bool', 14 => '::Float', 15 => '::Float' }.freeze
      DOP1_MEMBERS = [[:bytes, '::String'], [:endian, '::Symbol?']].freeze

      module_function

      # @return [String]
      def file(model, item)
        lines = Index.wrap(["module #{Naming.constant(item.family)}", *Index.indent(type(model, item)), 'end'])
        [Index::HEADER, *lines, ''].join("\n")
      end

      def type(model, item)
        case item
        when Enum then enum(item)
        when Dop2Class then dop2(item)
        else dop1(model, item)
        end
      end

      def enum(enum)
        # The app declares one enum without values, MissingEnumDefinitionInDopxFile.
        symbols = enum.values.empty? ? 'bot' : enum.values.map { it.first.inspect }.uniq.join(' | ')
        ["module #{Index.short(enum)}", "  extend #{OBJECTS}::Enum", '', "  type value = #{symbols}", '',
         '  VALUES: ::Hash[value, ::Integer]', 'end']
      end

      def opening(klass, kind)
        ["class #{Index.short(klass)} < ::Data", "  extend #{OBJECTS}::#{kind}Class",
         "  include #{OBJECTS}::#{kind}Value", '']
      end

      def members(members)
        keywords = members.map { |name, type| "?#{name}: #{type}" }.join(', ')
        readers = members.map { |name, type| "  attr_reader #{name}: #{type}" }
        [*readers, '', "  def self.new: (#{keywords}) -> instance"]
      end

      def dop2(klass)
        members = [*klass.fields.map { [it.member, "(#{field(it)})?"] }, [:raw, FIELDS]]
        [*opening(klass, 'Dop2'), '  ADDRESSES: ::Array[::Array[::Integer?]]',
         '  MEMBERS: ::Hash[::Symbol, [::Integer, ::Symbol, ::String?]]', '', *members(members),
         "  def self.from: (#{FIELDS} fields) -> instance", 'end']
      end

      def field(field)
        case field.kind
        when :enum then "#{OBJECTS}::#{field.type}::value | ::Integer"
        when :enum_array then "::Array[#{OBJECTS}::#{field.type}::value | ::Integer]"
        when :struct then "#{OBJECTS}::#{field.type}"
        when :struct_array then "::Array[#{OBJECTS}::#{field.type}]"
        else scalar(field)
        end
      end

      def scalar(field)
        case field.kind
        when :string then '::String'
        when :array then "::Array[#{SCALARS.fetch(field.wire - 16, '::Integer')}]"
        else SCALARS.fetch(field.wire, '::Integer')
        end
      end

      def dop1(model, klass)
        parts = [*klass.fields, *klass.sections, *klass.arrays].map { [it.member, "(#{dop1_type(it)})?"] }
        [*opening(klass, 'Dop1'), *dop1_constants(klass), '', *members([*parts, *DOP1_MEMBERS]),
         '  def self.from: (::String bytes, ?endian: ::Symbol?) -> instance',
         *Index.indent(Index.children(model, klass).flat_map { ['', *dop1(model, it)] }), 'end']
      end

      def dop1_constants(klass)
        pieces = '  WRITE_BYTES: ::Array[::Array[::Integer]]' if klass.write
        id = '  ID: ::String' if klass.id
        [*id, '  ENDIAN: ::Symbol?', *pieces, '  MEMBERS: ::Hash[::Symbol, ::Array[untyped]]']
      end

      def dop1_type(part)
        case part
        in Dop1Part[count: Integer] then '::Array[::Integer]'
        in Dop1Part then "#{OBJECTS}::#{part.type}"
        in { type: String } then "#{OBJECTS}::#{part.type}::value | ::Integer"
        else '::Integer'
        end
      end
    end
  end
end
