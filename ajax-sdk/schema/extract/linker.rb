# frozen_string_literal: true

require 'google/protobuf'
require 'google/protobuf/descriptor_pb'
require_relative 'java_literals'

module Schema
  module Extract
    # Pairs each method with the full names of its request and response messages, by the rules schema/README.md gives.
    class Linker
      FIELD_NUMBER = /([A-Z][A-Z0-9_]*)_FIELD_NUMBER = (\d+)/
      GET_DESCRIPTOR = /getDescriptor\(\)\s*\{\s*return (\w+)\./

      def self.normalize(name) = name.downcase.delete('_')

      # Stops before the first nested class, so that the inner messages of a oneof do not count.
      def self.field_numbers(text)
        text.split(/public static (?:final )?class /, 2).first.to_s.scan(FIELD_NUMBER)
            .to_h { |stem, number| [normalize(stem), number.to_i] }
      end

      # @param descriptors [Array<String>] FileDescriptorProto bytes
      # @param texts [Hash{String=>String}] each decompiled class by name
      def initialize(descriptors, texts)
        @texts = texts
        @fields = {}
        @simple = Hash.new { |simple, name| simple[name] = [] }
        descriptors.each { index(it) }
        @names = @fields.keys.to_set
        @files = files
      end

      # @return [Array(String, String), nil] the request and response of the method
      def pair(service, method, request, response)
        package = service.rpartition('.').first
        named = by_name(service, method) || by_lone(service)
        request = resolve(request, package) || named&.first
        response = resolve(response, package) || named&.last
        [request, response] if request && response
      end

      private

      def index(bytes)
        messages(bytes) do |full, message|
          @fields[full] = message.field.to_h { [self.class.normalize(it.name), it.number] }
          @simple[message.name] << full
        end
      end

      def messages(bytes, &)
        file = Google::Protobuf::FileDescriptorProto.decode(bytes)
        file.message_type.each { nested(file.package, it, &) }
      end

      def nested(scope, message, &)
        full = "#{scope}.#{message.name}"
        yield full, message
        message.nested_type.each { nested(full, it, &) }
      end

      # @return [Hash{String=>Array<String>}] each class building one descriptor to the messages that file holds
      def files
        @texts.filter_map do |name, text|
          descriptors = JavaLiterals.descriptors(text)
          next unless descriptors.one?

          names = []
          messages(descriptors.first) { |full, _| names << full }
          [name, names]
        end.to_h
      end

      def resolve(klass, package)
        return unless klass
        return by_descriptor(klass) || by_class_name(klass, package) if klass.end_with?('Request', 'Response')

        by_descriptor(klass) || by_fields(klass, package)
      end

      def by_descriptor(klass)
        text = @texts[klass] or return
        candidates = @files[text[GET_DESCRIPTOR, 1]] or return
        numbers = self.class.field_numbers(text)
        matches = candidates.select { @fields[it] == numbers }
        matches.first if matches.one?
      end

      def by_class_name(klass, package) = in_package(@simple[klass], package).min_by(&:length)

      def by_fields(klass, package)
        numbers = self.class.field_numbers(@texts[klass].to_s)
        return if numbers.empty?

        matches = in_package(@fields.select { |_, fields| fields == numbers }.keys, package)
        matches.first if matches.one?
      end

      def in_package(names, package) = names.select { it.start_with?("#{package}.") }

      def by_name(service, method)
        package, _, bare = service.rpartition('.')
        [method.sub(/\A./, &:upcase), bare.delete_suffix('Service')].each do |stem|
          pair = ["#{package}.#{stem}Request", "#{package}.#{stem}Response"]
          return pair if pair.all? { @names.include?(it) }
        end
        nil
      end

      def by_lone(service)
        package = service.rpartition('.').first
        depth = package.count('.') + 1
        lone = lambda do |suffix|
          found = @names.select { it.start_with?("#{package}.") && it.count('.') == depth && it.end_with?(suffix) }
          found.first if found.one?
        end
        request = lone['Request']
        response = lone['Response']
        [request, response] if request && response
      end
    end
  end
end
