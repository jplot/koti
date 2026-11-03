# frozen_string_literal: true

require_relative 'classes'
require_relative 'responses'

module Schema
  module Extract
    # One fromJson written by json_serializable, walked like the app's RAML classes. It also tells a key read twice,
    # for a null check, from one read once, and an enum, decoded through the map of its values.
    class BehaviorFromJson < FromJson
      NESTED = /\A\._\$(\w+)FromJson\z/
      ENUM = /\AMap<(\w+), String>\(\d+\) \{\z/

      def initialize(snapshot, name)
        super
        @reads = Hash.new(0)
      end

      # @return [Hash{String=>Hash}] by key, what {FromJson} tells of it, and how many times it was read
      def decoded(instructions) = fields(instructions).to_h { |key, field| [key, field.merge('reads' => @reads[key])] }

      private

      def load(register, offset)
        super
        enum = @snapshot.object(offset).to_s[ENUM, 1]
        describe('enum', enum) if enum
      end

      def call(target)
        case @snapshot.owner(target.hex).to_s
        when NESTED then describe('class', Regexp.last_match(1))
        when '.$enumDecode' then describe('always', true)
        else consume
        end
        @key = nil
      end

      def consume
        @reads[@key] += 1 if @key
        super
      end
    end

    # The classes of the app's automations that some roots reach, as hue.json describes a class. They come from
    # json_serializable, not from the API description, so the code alone tells which keys are required.
    class BehaviorClasses
      # @param snapshot [Snapshot]
      # @param taken [Array<String>] the classes of hue.json, whose names these classes cannot use
      def initialize(snapshot, taken:)
        @snapshot = snapshot
        @taken = taken
      end

      # @param roots [Array<String>] classes of the app
      # @return [Hash{String=>Hash}] the classes by name
      # @raise [ArgumentError] for a name hue.json takes, or a class without fromJson
      def read(roots)
        queue = roots.dup
        queue.each_with_object({}) do |origin, classes|
          next if classes.key?(name(origin))

          decoded = decoded(origin)
          fields = decoded.transform_values { field(it) }
          classes[name(origin)] = { 'origin' => origin, 'kind' => 'behavior', 'fields' => fields }
          queue.concat(decoded.values.filter_map { held(it) })
        end
      end

      private

      def decoded(origin)
        address, size = @snapshot.function("._$#{origin}FromJson")
        raise ArgumentError, "no fromJson for #{origin}" unless address

        BehaviorFromJson.new(@snapshot, origin).decoded(@snapshot.instructions(address, size))
      end

      def name(origin)
        origin.delete_prefix('Bridge').tap do |name|
          raise ArgumentError, "#{origin} would take the name #{name}, which hue.json has" if @taken.include?(name)
        end
      end

      def field(decoded)
        values = @snapshot.enum_values(decoded['enum'] || decoded['items'])
        field = { 'type' => type(decoded, values), 'required' => required?(decoded) }
        values ? field.merge('values' => values) : field
      end

      def type(decoded, values)
        return 'String' if decoded['enum']
        return { 'class' => name(decoded['class']) } if decoded['class']
        return { 'list' => values ? 'String' : item(decoded['items']) } if decoded['items']

        dart = decoded['type'].to_s.delete_suffix('?')
        Types.primitive(dart) || (dart.start_with?('Map<') ? 'Hash' : 'Object')
      end

      def item(dart) = Types.primitive(dart) || { 'class' => name(dart) }

      def required?(decoded)
        return decoded.key?('always') if decoded['enum']

        decoded['reads'] == 1 && !decoded['type'].to_s.end_with?('?')
      end

      def held(decoded)
        items = decoded['items']
        decoded['class'] || (items unless Types.primitive(items) || @snapshot.enum_values(items))
      end
    end
  end
end
