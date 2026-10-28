# frozen_string_literal: true

require 'json'

module Schema
  module Extract
    # aiohue's v2 dataclasses and enums, as aiohue_models.py reads them from its sources.
    class Aiohue
      SCRIPT = File.join(__dir__, 'aiohue_models.py')
      SUFFIXES = { 'update' => 'Put', 'add' => 'Post' }.freeze

      # @param models [String] aiohue's aiohue/v2/models directory
      def self.read(models)
        data = JSON.parse(IO.popen(['python3', '-I', SCRIPT, models], &:read))
        raise ArgumentError, "no aiohue class in #{models}: give its aiohue/v2/models" if data.fetch('classes').empty?

        new(data)
      end

      # A response field aiohue gives neither a default nor None is never absent.
      def self.required?(field) = field['default'].nil? && !field['type'].end_with?('| None')

      # @return [String] the class or enum a field holds, or holds a list of
      def self.type_name(field) = field['type'].delete_suffix(' | None').then { it[/\Alist\[(\w+)\]\z/, 1] || it }

      def initialize(data)
        @classes = data.fetch('classes')
        @enums = data.fetch('enums')
        @by_type = @classes.keys.each_with_object({}) { |name, by_type| index(name, by_type) }
      end

      def class?(name) = @classes.key?(name)

      def values(enum) = @enums.dig(enum, 'values')

      def fields(name)
        own = @classes[name]['fields']
        inherited = @classes[name]['bases'].flat_map { class?(it) ? fields(it) : [] }
        inherited.reject { |field| own.any? { it['name'] == field['name'] } } + own
      end

      def field(name, key) = fields(name).find { it['name'] == key }

      # @param kind [String] +added+ for a response, +update+ or +add+ for a request
      # @return [String, nil] aiohue's class for a resource type: +Light+, then +LightPut+ and +LightPost+
      def class_for(type, kind)
        added = @by_type[[type, 'added']]
        return added if kind == 'added'

        request = "#{added}#{SUFFIXES.fetch(kind)}"
        @by_type[[type, kind]] || (request if added && class?(request))
      end

      private

      # A resource class defaults its +type+ to its resource type: +ResourceTypes.LIGHT+.
      def index(name, by_type)
        type = fields(name).rfind { it['name'] == 'type' }&.fetch('default')
        return unless type&.start_with?('ResourceTypes.')

        by_type[[type.split('.').last.downcase, name.end_with?('Post') ? 'add' : 'added']] ||= name
      end
    end
  end
end
