# frozen_string_literal: true

require 'json'
require 'zlib'

module Schema
  module Generate
    Dop2Class = Data.define(:family, :name, :constant, :fields, :addresses)
    Dop2Field = Data.define(:member, :index, :kind, :wire, :type)
    Dop1Class = Data.define(:family, :name, :constant, :id, :endian, :sections, :arrays, :fields, :write, :write_bytes)
    Dop1Field = Data.define(:member, :kind, :offset, :size, :length, :type)
    Enum = Data.define(:family, :name, :constant, :values)

    # A section or an array of a Dop1 object: a section has a length, an array a count of items of a width.
    Dop1Part = Data.define(:type, :offset, :length, :computed, :count, :width) do
      def initialize(length: nil, computed: nil, count: nil, width: nil, **) = super
    end

    # The Ruby names of the app's ones.
    module Naming
      RESERVED = [*Data.public_instance_methods, :raw, :to_fields, :to_bytes].freeze
      GERMAN = { 'ä' => 'ae', 'ö' => 'oe', 'ü' => 'ue', 'Ä' => 'Ae', 'Ö' => 'Oe', 'Ü' => 'Ue', 'ß' => 'ss' }.freeze

      module_function

      # @return [String] +GLOBAL_PS_Select+ as +GlobalPsSelect+, a nested +Outer/Inner+ as +Outer::Inner+
      def constant(name) = ascii(name).split('/').map { camelize(it) }.join('::')

      # @return [String] each word capitalized, a word in capitals lowered after its first letter
      def camelize(name) = name.split('_').map { it == it.upcase ? it.capitalize : it[0].upcase + it[1..] }.join

      # @return [Symbol] the getter in snake_case, with a final +_+ when a value class already has a method of that name
      def member(name)
        member = snake(name).squeeze('_').delete_prefix('_').delete_suffix('_').to_sym
        RESERVED.include?(member) ? :"#{member}_" : member
      end

      # The prefix is the longest one ending in +_+ that every value shares, or that the values but 0 share when 0
      # shares none. The rest keeps its underscores: the hob tells +Kochstufe_1+ from +Kochstufe_1_+.
      #
      # @param values [Array(String, Integer)] name and number of each value
      # @return [Array<Symbol>] the short symbol of each value
      # @raise [ArgumentError] when two values get the same symbol
      def symbols(constant, values)
        names = values.map(&:first)
        others = values.reject { it.last.zero? }.map(&:first)
        prefix = common_prefix(names)
        prefix = common_prefix(others) if prefix.empty?
        distinct!(constant, names.map { snake(it.delete_prefix(prefix)).to_sym })
      end

      # The first and last names in sort order share the prefix every name shares. One name shares nothing: 7 enums
      # have one value (+Version_1+), and 34 one beside 0 (+ohne_Topferkennung+).
      def common_prefix(names)
        return '' if names.size < 2

        first = names.min.to_s
        size = first.each_char.zip(names.max.to_s.each_char).take_while { |left, right| left == right }.size
        first[0, size].to_s[/\A.*_/].to_s
      end

      # @raise [ArgumentError] when two of +names+ are the same
      def distinct!(where, names)
        twice = names.tally.select { |_, count| count > 1 }.keys
        raise ArgumentError, "#{where}: #{twice.join(', ')} given twice" if twice.any?

        names
      end

      def snake(name) = ascii(name).gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase

      def ascii(name) = name.gsub(/[#{GERMAN.keys.join}]/, GERMAN)
    end

    # The objects of objects.json.gz under Ruby names: each constant below Miele::Sdk::Objects (+Oven::GlobalPsSelect+),
    # each field type as the constant of the class or enum it names, nil for a plain number.
    class Model
      # @param path [String] objects.json.gz
      # @return [Model]
      def self.load(path) = new(JSON.parse(Zlib.gunzip(File.binread(path))))

      # @return [Array<Dop2Class>]
      attr_reader :dop2

      # @return [Array<Dop1Class>]
      attr_reader :dop1

      # @return [Array<Enum>]
      attr_reader :enums

      # @param data [Hash] +dop2+, +dop1+ and +enums+, as objects.json.gz holds them
      # @raise [ArgumentError] when two objects of a family get one constant, or two fields of an object one member
      def initialize(data)
        @constants = constants(data.values.flatten)
        @dop2 = data['dop2'].map { dop2_class(it) }
        @dop1 = data['dop1'].map { dop1_class(it) }
        @enums = data['enums'].map { enum(it) }
      end

      private

      def constants(entries)
        named = entries.to_h do |entry|
          [[entry['family'], entry['name']], "#{Naming.constant(entry['family'])}::#{Naming.constant(entry['name'])}"]
        end
        Naming.distinct!('objects', named.values)
        named
      end

      def constant(entry) = @constants.fetch([entry['family'], entry['name']])

      def type(entry, part) = @constants[[entry['family'], part['type']]]

      def enum(entry)
        symbols = Naming.symbols(constant(entry), entry['values'])
        Enum.new(family: entry['family'], name: entry['name'], constant: constant(entry),
                 values: symbols.zip(entry['values'].map(&:last)))
      end

      def dop2_class(entry)
        fields = entry['fields'].map do |field|
          Dop2Field.new(member: Naming.member(field['name']), index: field['index'], kind: field['kind'].to_sym,
                        wire: field['wire'], type: type(entry, field))
        end
        Dop2Class.new(family: entry['family'], name: entry['name'], constant: constant(entry),
                      fields: members!(entry, fields), addresses: entry['addresses'])
      end

      def dop1_class(entry)
        Dop1Class.new(family: entry['family'], name: entry['name'], constant: constant(entry), id: entry['id'],
                      endian: entry['endian']&.to_sym, **parts(entry), fields: members!(entry, dop1_fields(entry)),
                      write: entry['write'], write_bytes: entry['write_bytes'])
      end

      def parts(entry)
        %w[sections arrays].to_h do |key|
          [key.to_sym, entry[key].map { Dop1Part.new(**it.transform_keys(&:to_sym), type: type(entry, it)) }]
        end
      end

      def dop1_fields(entry)
        entry['fields'].map do |field|
          Dop1Field.new(member: Naming.member(field['name']), kind: field['kind'].to_sym, offset: field['offset'],
                        size: field['size'], length: field['length'], type: type(entry, field))
        end
      end

      def members!(entry, fields)
        Naming.distinct!(constant(entry), fields.map(&:member))
        fields
      end
    end
  end
end
