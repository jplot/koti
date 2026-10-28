# frozen_string_literal: true

module Schema
  module Extract
    # Types of the schema from the Dart types the app decodes.
    module Types
      PRIMITIVES = {
        'String' => 'String', '_OneByteString' => 'String', 'int' => 'Integer', 'num' => 'Numeric',
        'double' => 'Numeric', 'bool' => 'Boolean', 'Map<String, Object?>' => 'Hash', 'Map<String, Object>' => 'Hash',
        'Object' => 'Object'
      }.freeze

      module_function

      def primitive(dart) = PRIMITIVES[dart]

      # @param decoded [Hash] a field as {Responses} reads it
      # @param response [Boolean] whether it belongs to a response class, named without the app's +Added+ suffix
      def dart(decoded, response:)
        if decoded['class'] then { 'class' => name(decoded['class'], response:) }
        elsif decoded['items']
          { 'list' => primitive(decoded['items']) || { 'class' => name(decoded['items'], response:) } }
        else primitive(decoded['type'].to_s.delete_suffix('?'))
        end
      end

      def name(dart_class, response:) = response ? dart_class.delete_suffix('Added') : dart_class

      # @return [String, nil] the class a type holds, or holds a list of
      def held(type) = (type['class'] || (type['list']['class'] if type['list'].is_a?(Hash)) if type.is_a?(Hash))
    end

    # The schema's classes as the app's code describes them: a response from what its fromJson decodes, a request from
    # what its toJson writes. A field none of them types is left untyped, as an +Object+.
    class Classes
      attr_reader :all

      # @param report [Hash{String=>Array<String>}] collects what the reader should check
      def initialize(responses, requests, report)
        @added = responses.fetch('added')
        @requests = requests
        @report = report
        @all = {}
        @untyped = []
      end

      def request?(kind, name) = @requests[kind].key?(name)

      def requests(kind) = @requests[kind].keys

      def untyped?(name, key) = @untyped.include?([name, key])

      def typed(name, key) = @untyped.delete([name, key])

      # @return [Array<String>] +Class.field+ of each field still untyped
      def untyped
        @all.flat_map { |name, cls| cls['fields'].keys.select { untyped?(name, it) }.map { "#{name}.#{it}" } }
      end

      # @return [String] the name of the response class built from the app's +*Added+ class
      def response(added)
        name = Types.name(added, response: true)
        return name if @all.key?(name)

        fields = (@all[name] = { 'origin' => added, 'kind' => 'response', 'fields' => {} })['fields']
        @added.fetch(added).each do |key, decoded|
          type = Types.dart(decoded, response: true)
          @report['response field left untyped'] << "#{name}.#{key}" unless type
          fields[key] = { 'type' => type || 'Object', 'required' => false }
          response(added_class(decoded)) if added_class(decoded)
        end
        name
      end

      def request(name, kind)
        return name if @all.key?(name)

        fields = (@all[name] = { 'origin' => name, 'kind' => kind, 'fields' => {} })['fields']
        @requests[kind].fetch(name)['written'].each do |key, written|
          next if key == 'id'

          type = request_type(name, kind, key, written)
          @untyped << [name, key] unless type
          fields[key] = { 'type' => type || 'Object', 'required' => written['required'] }
          request(Types.held(type), kind) if Types.held(type)
        end
        name
      end

      private

      def added_class(decoded) = decoded['class'] || (decoded['items'] if @added.key?(decoded['items']))

      def request_type(name, kind, key, written)
        decoded = @requests[kind][name]['decoded']&.dig(key)
        return Types.dart(decoded, response: false) if decoded

        declared = @requests[kind][name]['declared'][written['offset']]
        return { 'class' => declared } if declared && request?(kind, declared)

        Types.primitive(declared) || { 'double' => 'Numeric', 'int' => 'Integer' }[written['kind']] ||
          counterpart(name, kind, key)
      end

      def counterpart(name, kind, key)
        mirror = @added[name.sub(/(Update|Add)\z/, 'Added')]&.dig(key)
        return unless mirror

        held = mirror['class'] || mirror['items']
        return Types.primitive(mirror['type'].to_s.delete_suffix('?')) || 'Object' unless held
        return { 'list' => Types.primitive(held) } if Types.primitive(held)

        counterpart_class("#{name}.#{key}", kind, held, list: !mirror['class'])
      end

      # The response's +DimmingFeatureAdded+ is the request's +DimmingFeatureUpdate+, if the app has one.
      def counterpart_class(field, kind, held, list:)
        candidate = held.sub(/Added\z/, kind == 'update' ? 'Update' : 'Add')
        @report['request type inferred from the response class'] << "#{field} -> #{candidate}"
        return unless request?(kind, candidate)

        list ? { 'list' => { 'class' => candidate } } : { 'class' => candidate }
      end
    end
  end
end
