# frozen_string_literal: true

require_relative 'snapshot'

module Schema
  module Extract
    # Reads the fromJson of the classes the app generates from the API description, in its RAML library: the JSON
    # keys each decodes, with their Dart type, class or list item.
    class Responses
      KINDS = %w[added update add].freeze

      def initialize(snapshot) = @snapshot = snapshot

      # @return [Hash{String=>Hash}] by kind (+added+, +update+, +add+) and class, the fields its fromJson decodes: nil
      #   when blutter lists no fromJson
      def read
        KINDS.to_h do |kind|
          listing = File.read(@snapshot.source("bridge_control/src/raml_code.#{kind}.dart"))
          [kind, listing.scan(/^class (\w+) extends/).flatten.to_h { [it, fields(it)] }]
        end
      end

      private

      def fields(name)
        address, size = @snapshot.function("#{name}.#{name}.fromJson")
        FromJson.new(@snapshot, name).fields(@snapshot.instructions(address, size)) if address
      end
    end

    # One fromJson walked in code order. Each key is a pool string loaded into x2, read once a call consumes it; the
    # Dart types and type arguments loaded after it, and the fromJson it calls, describe its value.
    class FromJson
      STEPS = {
        /add\s+(x\d+), x27, #0x(\h+), lsl #12/ => :page,
        /ldr\s+(x\d+), \[x27, #0x(\h+)\]/ => :pool_load,
        /ldr\s+(x\d+), \[(x\d+), #0x(\h+)\]/ => :paged_load,
        /\Ablr\s+x30/ => :dispatch,
        /\Abl\s+0x(\h+)/ => :call
      }.freeze

      def initialize(snapshot, name)
        @snapshot = snapshot
        @name = name
        @pages = {}
        @fields = {}
      end

      def fields(instructions)
        instructions.each { step(it) }
        @fields
      end

      private

      def step(instruction)
        STEPS.each do |pattern, handler|
          next unless (match = pattern.match(instruction))

          return send(handler, *match.captures)
        end
      end

      def page(register, offset) = @pages[register] = offset.hex << 12

      def pool_load(register, offset) = load(register, offset.hex)

      def paged_load(register, base, offset) = (load(register, @pages.delete(base) + offset.hex) if @pages[base])

      def load(register, offset)
        object = @snapshot.object(offset)
        @key = object.to_s[/\AString: "(.*)"\z/, 1] if register == 'x2'
        describe('type', Regexp.last_match(1)) if object =~ /\AType: (.*)\z/
        describe('items', Regexp.last_match(1)) if object =~ /\ATypeArguments: <(\w+)>\z/
      end

      def dispatch = consume

      def call(target)
        owner = @snapshot.owner(target.hex)
        owner&.match?(/\A(\w+)\.\1\.fromJson\z/) ? describe('class', owner.split('.').first) : consume
        @key = nil
      end

      def consume
        @value = @fields[@key] ||= {} if @key
        @key = nil
      end

      def describe(slot, value) = (@value[slot] ||= value if @value && !(slot == 'class' && value == @name))
    end
  end
end
