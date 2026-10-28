# frozen_string_literal: true

module Schema
  module Extract
    # The JSON classes of the IL ikdasm prints for some assemblies: each field by its Newtonsoft key, with its CLR type
    # and whether the app lets it be null. Only properties are read, not public fields, nor the properties a class
    # inherits or those of a nested class.
    class Il
      PROPERTY = '  .property instance '
      CONTEXT = /\A  \.custom .*NullableContextAttribute::\.ctor\(uint8\) = \( 01 00 (\h\h)/
      NULLABLE = /\A(?:\[[^\]]+\])?System\.Nullable`1</
      PREFIX = /\A(?:class |valuetype )?(?:\[[^\]]+\])?/
      PRIMITIVE = /\A(?:bool|char|u?int(?:8|16|32|64)|float(?:32|64))\z/
      # ikdasm never writes +valuetype+: an enum reads +class Ns.Enum+, so value types are known from their definition.
      SYSTEM_VALUES = %w[System.DateTime System.DateTimeOffset System.TimeSpan System.Guid System.Decimal].freeze
      NAMED_KEY = [0x54, 0x0E, 0x0C, *'PropertyName'.bytes].freeze

      def self.read(paths)
        il = new
        paths.each { il.read(it) }
        il.classes
      end

      def initialize
        @classes = {}
        @values = SYSTEM_VALUES.dup
      end

      def read(path) = File.foreach(path, encoding: 'UTF-8') { step(it.chomp.scrub) }

      # @return [Hash{String=>Hash}] by class, its fields by key (CLR type and whether it may be null), and whether it
      #   gathers the keys it does not declare
      def classes
        @classes.transform_values do |found|
          { 'fields' => found[:fields].transform_values { { 'type' => it[:type], 'nullable' => nullable?(it) } },
            'extension' => found[:extension] }
        end
      end

      private

      def step(line)
        if @blob then blob(line)
        elsif @header then header(line)
        elsif @type then @property = { type: @type, name: line.strip.delete_suffix('()') }.tap { @type = nil }
        elsif @property then property(line)
        else outside(line)
        end
      end

      def outside(line)
        if line.start_with?('.class ') then open_class(line[/\A\.class (?:[a-z]+ )*(\S+)/, 1].sub(/<.*/, ''))
        elsif line.start_with?(PROPERTY) then open_property(line.delete_prefix(PROPERTY).strip)
        elsif (context = line[CONTEXT, 1]) then @context = context.hex
        end
      end

      def open_class(name)
        @name = name
        @class = @classes[name] = { fields: {}, extension: false }
        @context = nil
        @header = true
      end

      def header(line)
        @header = false
        @values << @name if line[/\A\s+extends (\S+)/, 1]&.end_with?('System.Enum', 'System.ValueType')
      end

      def open_property(declaration)
        return @property = { ignored: true } if declaration.match?(/\(.+\)\z/) # an indexer
        return @type = declaration unless declaration.end_with?('()')

        type, _, name = declaration.rpartition(' ')
        @property = { type:, name: name.delete_suffix('()') }
      end

      def property(line)
        if line.start_with?('  } // end of property') then close_property
        elsif line.include?('JsonIgnoreAttribute') then @property[:ignored] = true
        elsif line.include?('JsonExtensionDataAttribute') then @property[:extension] = true
        elsif line.include?('NullableAttribute::.ctor(uint8') then @property[:flag] = flag(line)
        elsif line.match?(/JsonProperty(?:Name)?Attribute::\.ctor\((?:string)?\)/) then open_blob(line)
        end
      end

      # +NullableAttribute(uint8)+ holds one flag; the first of +NullableAttribute(uint8[])+ is the property's own.
      def flag(line)
        bytes = line[/= \(([\h ]+)/, 1].split.map(&:hex)
        line.include?('uint8[]') ? bytes[6] : bytes[2]
      end

      def open_blob(line)
        @named = line.include?('.ctor()')
        @blob = +''
        blob(line.split('(', 3).last)
      end

      def blob(line)
        text = line.sub(%r{//.*}, '')
        @blob << text[/[\h ]*/]
        return unless text.include?(')')

        @property[:key] = key(@blob.split.map(&:hex))
        @blob = nil
      end

      # +JsonProperty("Key")+ holds the key as its argument, +JsonProperty(PropertyName = "Key")+ among named ones.
      def key(bytes)
        return string(bytes, 2) unless @named

        at = bytes.each_cons(NAMED_KEY.size).find_index(NAMED_KEY)
        string(bytes, at + NAMED_KEY.size) if at
      end

      def string(bytes, at) = bytes[at + 1, bytes[at]].pack('C*').force_encoding('UTF-8')

      # Records add EqualityContract, which Newtonsoft leaves out as it is not public.
      def close_property
        property = @property
        @property = nil
        return if property[:ignored] || property[:name] == 'EqualityContract'
        return @class[:extension] = true if property[:extension]

        @class[:fields][property[:key] || property[:name]] = { type: property[:type],
                                                               flag: property[:flag] || @context }
      end

      def nullable?(field)
        type = field[:type]
        return true if type.match?(NULLABLE)
        return false if type.match?(PRIMITIVE) || @values.include?(type.sub(PREFIX, ''))

        field[:flag] != 1
      end
    end
  end
end
