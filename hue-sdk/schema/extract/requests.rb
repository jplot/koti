# frozen_string_literal: true

require_relative 'snapshot'

module Schema
  module Extract
    # Reads the toJson of the app's request classes (+*Update+, +*Add+): the keys each writes, and which it writes
    # without a null check, so always.
    class Requests
      KINDS = %w[update add].freeze
      # A toJson this small only calls the body it shares with identical classes, sometimes through a second one.
      TEAR_OFF = 0x48

      # @param responses [Hash] what {Responses#read} returns
      def initialize(snapshot, responses)
        @snapshot = snapshot
        @responses = responses
      end

      # @return [Hash{String=>Hash}] by kind and class: the fields fromJson decodes, the keys toJson writes and the
      #   type blutter gives a field, by offset
      def read
        KINDS.to_h do |kind|
          declared = declared(kind)
          [kind, @responses[kind].to_h do |name, decoded|
            [name, { 'decoded' => decoded, 'written' => written(name), 'declared' => declared[name] }]
          end]
        end
      end

      private

      def written(name)
        address, size = @snapshot.function("#{name}.toJson")
        return unless address

        address, size = body(address, size)
        address ? ToJson.new(@snapshot).written(@snapshot.instructions(address, size)) : {}
      end

      def body(address, size)
        3.times do
          break if size > TEAR_OFF

          return unless (address = called(@snapshot.instructions(address, size)))

          size = 4 * (@snapshot.instructions(address, 0x1000).index { it.start_with?('ret') } + 1)
        end
        [address, size]
      end

      def called(wrapper)
        wrapper.take(wrapper.index { it.start_with?('ret') }).filter_map { it[/\Abl\s+0x(\h+)/, 1]&.hex }.first
      end

      # blutter prints the static type of a field when the snapshot keeps it: "  AlertFeatureUpdate field_34;".
      def declared(kind)
        owner = nil
        File.foreach(@snapshot.source("bridge_control/src/raml_code.#{kind}.dart"))
            .each_with_object(Hash.new { |hash, name| hash[name] = {} }) do |line, declared|
          owner = Regexp.last_match(1) if line =~ /\Aclass (\w+) extends/
          declared[owner][Regexp.last_match(2).hex] = Regexp.last_match(1) if line =~ /\A {2}(\S+) field_(\h+);/
        end
      end
    end

    # One toJson walked in code order. A call with a pool string in x2 writes that key, with the field loaded since the
    # previous key (optional if null-checked against w22) or else the constant in x3: +SceneMappingAdd+ always sends
    # +"algorithm": "spatial"+. A string loaded into x16 right before a field load is a map literal's key, always sent.
    class ToJson
      FIELDS = {
        /\Aldur\s+(w\d+), \[x\d+, #0x(\h+)\]/ => 'pointer',
        /\Aldur\s+(d\d+), \[x\d+, #0x(\h+)\]/ => 'double',
        /\Aldur\s+(x\d+), \[x\d+, #0x(\h+)\]/ => 'int'
      }.freeze
      STEPS = {
        /ldr\s+x16, \[x27, #0x(\h+)\]/ => :literal,
        /ldr\s+x16, \[x16, #0x(\h+)\]/ => :paged_literal,
        /\Acmp\s+(w\d+), w22/ => :check,
        /add\s+(x\d+), x27, #0x(\h+), lsl #12/ => :page,
        /ldr\s+x2, \[x27, #0x(\h+)\]/ => :key,
        /ldr\s+x2, \[(x\d+), #0x(\h+)\]/ => :paged_key,
        /\Aldr\s+x3, \[x27, #0x(\h+)\]/ => :constant,
        /\Aldr\s+x3, \[x3, #0x(\h+)\]/ => :paged_constant,
        /\Amov\s+x3, #0x\h+\z/ => :integer,
        /\Ablr?\s/ => :call
      }.freeze

      def initialize(snapshot)
        @snapshot = snapshot
        @pages = {}
        @written = {}
      end

      def written(instructions)
        instructions.each { step(it) }
        @written
      end

      private

      def step(instruction)
        field = field(instruction)
        if field && @literal
          write(@literal, field, required: true)
          return @literal = nil
        end

        @load = field if field
        STEPS.each do |pattern, handler|
          next unless (match = pattern.match(instruction))

          return send(handler, *match.captures)
        end
      end

      def field(instruction)
        FIELDS.each do |pattern, kind|
          next unless (match = pattern.match(instruction))

          offset = match[2].hex
          # A 64-bit load from an even offset reads the object header, not a field.
          return { register: match[1], offset: offset + 1, kind:, checked: false } unless kind == 'int' && offset.even?
        end
        nil
      end

      def write(key, load, required:)
        @written[key] = { 'offset' => load[:offset], 'kind' => load[:kind], 'required' => required }
      end

      def literal(offset) = @literal = @snapshot.string(offset.hex)

      def paged_literal(offset) = (@literal = @snapshot.string(@pages.delete('x16') + offset.hex) if @pages['x16'])

      def check(register) = (@load[:checked] = true if @load && @load[:register] == register)

      def page(register, offset) = @pages[register] = offset.hex << 12

      def key(offset) = @key = @snapshot.string(offset.hex)

      def paged_key(base, offset) = (@key = @snapshot.string(@pages.delete(base) + offset.hex) if @pages[base])

      def constant(offset) = string(offset.hex)

      def paged_constant(offset) = (string(@pages.delete('x3') + offset.hex) if @pages['x3'])

      def string(offset) = @constant = ('string' if @snapshot.string(offset))

      def integer = @constant = 'int'

      def call
        return unless @key

        if @load then write(@key, @load, required: !@load[:checked])
        elsif @constant then @written[@key] = { 'kind' => @constant, 'required' => true }
        end
        @key = @load = @constant = nil
      end
    end
  end
end
