# frozen_string_literal: true

require_relative 'aiohue'
require_relative 'classes'

module Schema
  module Extract
    # Pairs the schema's classes with aiohue's, which give the values of the enums, which response fields are always
    # there, which request fields are optional, and the type of the request fields the app's code leaves untyped.
    class Pairing
      PRIMITIVES = {
        'str' => 'String', 'int' => 'Integer', 'float' => 'Numeric', 'bool' => 'Boolean', 'dict' => 'Hash'
      }.freeze

      def initialize(classes, aiohue, report)
        @classes = classes
        @aiohue = aiohue
        @report = report
        @pairs = Hash.new { |pairs, name| pairs[name] = [] }
      end

      def pair(ours, theirs)
        return unless @classes.all[ours] && @aiohue.class?(theirs) && !@pairs[ours].include?(theirs)

        @pairs[ours] << theirs
        @classes.all[ours]['fields'].each do |key, field|
          counterpart = @aiohue.field(theirs, key)
          pair_field(field, counterpart) if counterpart
        end
      end

      # @param sent [Boolean] whether the field is one of a request, then required unless aiohue lets it be None
      # @return [Boolean, nil] whether every aiohue class paired with ours requires the field, nil when none is paired
      def required(name, key, sent:)
        return if @pairs[name].empty?

        @pairs[name].all? do |theirs|
          field = @aiohue.field(theirs, key)
          field && (sent ? !field['type'].end_with?('| None') && field['default'] != 'None' : Aiohue.required?(field))
        end
      end

      # A field typed from aiohue may name a class not paired yet, whose own untyped fields the next pass types.
      def type_untyped
        loop do
          requests = @classes.all.reject { |_, request| request['kind'] == 'response' }
          typed = requests.flat_map do |name, request|
            request['fields'].filter_map { |key, field| type(name, key, field) if @classes.untyped?(name, key) }
          end
          break if typed.empty?
        end
      end

      private

      def pair_field(field, counterpart)
        held = Types.held(field['type'])
        pair(held, Aiohue.type_name(counterpart)) if held
        enum(field, counterpart)
      end

      def enum(field, counterpart)
        values = @aiohue.values(Aiohue.type_name(counterpart))
        field['values'] ||= values if values
      end

      def type(name, key, field)
        counterpart = @pairs[name].filter_map { @aiohue.field(it, key) }.first
        return unless counterpart && (type = from_aiohue(counterpart['type'], @classes.all[name]['kind']))

        field['type'] = type
        @classes.typed(name, key)
        enum(field, counterpart)
        @report['request type taken from aiohue'] << "#{name}.#{key} -> #{type.to_json}"
      end

      def from_aiohue(type, kind)
        type = type.delete_suffix(' | None')
        if (item = type[/\Alist\[(\w+)\]\z/, 1]) then (held = from_aiohue(item, kind)) && { 'list' => held }
        elsif PRIMITIVES[type] then PRIMITIVES[type]
        elsif @aiohue.values(type) then 'String'
        elsif @aiohue.class?(type) then request_class(type, kind)
        end
      end

      # aiohue's +LightPut+ or +DimmingFeaturePut+ is the app's +LightUpdate+ or +DimmingUpdate+.
      def request_class(theirs, kind)
        suffix = kind == 'update' ? 'Update' : 'Add'
        stem = theirs.sub(/(Put|Post|Base)\z/, '')
        names = ["#{theirs}#{suffix}", "#{stem}#{suffix}", "#{stem.delete_suffix('Feature')}#{suffix}"]
        found = names.find { @classes.request?(kind, it) } ||
                @classes.requests(kind).select { it.start_with?(stem) && it.end_with?(suffix) }
                        .then { it.first if it.one? }
        { 'class' => @classes.request(found, kind) }.tap { pair(found, theirs) } if found
      end
    end
  end
end
