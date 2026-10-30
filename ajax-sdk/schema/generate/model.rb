# frozen_string_literal: true

require 'zlib'
require 'google/protobuf'
require 'google/protobuf/descriptor_pb'

module Schema
  module Generate
    # A message the gem gets a value class for. +outcome+ names its +failure+ or +error+ member when that member
    # shares a oneof with +success+.
    Message = Data.define(:full_name, :constant, :file, :fields, :oneofs, :outcome)

    # A real oneof of a message: its protobuf name, the Ruby method telling which member is set, and its members.
    Oneof = Data.define(:name, :reader, :choices)

    Field = Data.define(:name, :key, :number, :kind, :type, :label, :presence, :map)

    # A field: its Ruby name, its +to_h+ key, and +map+ as its key and value fields when it is a map.
    class Field
      # @return [Boolean] whether its member may be nil: a scalar or an enum holds its protobuf default unless it
      #   sits in a oneof or is +optional+
      def nilable? = !presence.nil? || %i[message timestamp duration wrapper].include?(kind)

      # @return [Boolean] whether it is repeated, and not a map
      def list? = label == :repeated && map.nil?
    end

    # An enum and its values, each as its protobuf name and its short symbol, in the order of the descriptor.
    Enum = Data.define(:full_name, :constant, :file, :values)

    # The Ruby names of protobuf ones.
    module Naming
      RESERVED = [*Data.public_instance_methods, :raw, :to_message].freeze

      module_function

      # @return [Symbol] the name, with a final +_+ when a value class already has a method of that name
      def member(name) = RESERVED.include?(name.to_sym) ? :"#{name}_" : name.to_sym

      # @return [String] +stream_light_devices+ as +StreamLightDevices+
      def camelize(segment) = segment.split('_').map { it[0].to_s.upcase + it[1..].to_s }.join

      # The prefix is the longest one ending in +_+ that every value shares, or every value but 0 when 0 shares none.
      #
      # @param values [Array<Google::Protobuf::EnumValueDescriptorProto>]
      # @return [Array<Symbol>] the short symbol of each value
      # @raise [ArgumentError] when two values get the same symbol, or one gets none
      def symbols(full_name, values)
        prefix = common_prefix(values.map(&:name))
        prefix = common_prefix(values.reject { it.number.zero? }.map(&:name)) if prefix.empty?
        symbols = values.map { it.name.delete_prefix(prefix).downcase.to_sym }
        raise ArgumentError, "#{full_name}: a value has no name left" if symbols.include?(:'')

        distinct!(full_name, symbols)
      end

      # The first and last names in sort order share the prefix every name shares.
      def common_prefix(names)
        first = names.min.to_s
        size = first.each_char.zip(names.max.to_s.each_char).take_while { |left, right| left == right }.size
        first[0, size].to_s[/\A.*_/].to_s
      end

      # @return [Array<Symbol>] the members
      # @raise [ArgumentError] when two of them have the same name
      def distinct!(full_name, members)
        twice = members.tally.select { |_, count| count > 1 }.keys
        raise ArgumentError, "#{full_name}: #{twice.join(', ')} given twice" if twice.any?

        members
      end
    end

    # The fields, oneofs and outcome of a message descriptor.
    module Shapes
      WRAPPERS = %w[Double Float Int64 UInt64 Int32 UInt32 Bool String Bytes]
                 .to_h { ["google.protobuf.#{it}Value", it.downcase.to_sym] }.freeze
      CONVERTED = { 'google.protobuf.Timestamp' => :timestamp, 'google.protobuf.Duration' => :duration,
                    **WRAPPERS.transform_values { :wrapper } }.freeze

      module_function

      # @param entries [Hash{String=>Google::Protobuf::DescriptorProto}] the map entries, by full name
      # @return [Field]
      def field(descriptor, entries)
        type = descriptor.type_name.delete_prefix('.')
        Field.new(name: Naming.member(descriptor.name), key: descriptor.name.to_sym, number: descriptor.number,
                  kind: kind(descriptor, type), type: type.empty? ? scalar(descriptor) : type, label: label(descriptor),
                  presence: presence(descriptor), map: map(type, entries))
      end

      def label(descriptor) = descriptor.label.to_s.delete_prefix('LABEL_').downcase.to_sym

      def map(type, entries) = entries[type]&.field&.map { field(it, entries) }

      def kind(descriptor, type)
        case descriptor.type
        when :TYPE_MESSAGE then CONVERTED.fetch(type, :message)
        when :TYPE_ENUM then :enum
        else :scalar
        end
      end

      def scalar(descriptor) = descriptor.type.to_s.delete_prefix('TYPE_').downcase.to_sym

      def presence(descriptor)
        return :optional if descriptor.proto3_optional

        :oneof if descriptor.has_oneof_index?
      end

      # A proto3 +optional+ field sits alone in a synthetic oneof, which gets no reader.
      #
      # @param fields [Array<Field>] the fields of +descriptor+, in its order
      # @return [Array<Oneof>]
      def oneofs(descriptor, fields)
        declared = descriptor.field.to_a
        descriptor.oneof_decl.each_with_index.filter_map do |oneof, index|
          members = members(declared, index)
          next if members.all? { declared[it].proto3_optional }

          Oneof.new(name: oneof.name, reader: Naming.member(oneof.name), choices: members.map { fields[it].name })
        end
      end

      def members(declared, index)
        declared.each_index.select { declared[it].has_oneof_index? && declared[it].oneof_index == index }
      end

      # @return [String, nil] +failure+ or +error+, when it shares a oneof with +success+
      def outcome(descriptor)
        success = descriptor.field.find { it.name == 'success' }
        return unless success&.has_oneof_index? && !success.proto3_optional

        %w[failure error].find do |name|
          descriptor.field.any? { it.name == name && it.has_oneof_index? && it.oneof_index == success.oneof_index }
        end
      end
    end

    # The cloud types the methods of methods.tsv reach, under the Ruby names schema/README.md gives them.
    class Model
      Type = Data.define(:descriptor, :file, :package, :parent)
      ROOT = 'Ajax::Sdk::Cloud::Messages'
      private_constant :Type, :ROOT

      # @param directory [String] a schemas/ directory holding descriptors.pb.gz and methods.tsv
      # @return [Model]
      def self.load(directory)
        rpcs = File.readlines(File.join(directory, 'methods.tsv'), chomp: true).map { it.split("\t") }
        new(Zlib.gunzip(File.binread(File.join(directory, 'descriptors.pb.gz'))), rpcs)
      end

      # @param descriptors [String] the bytes of a FileDescriptorSet
      # @param rpcs [Array<Array(String, String, String, String)>] path, call type, request and response
      def initialize(descriptors, rpcs)
        @types = {}
        Google::Protobuf::FileDescriptorSet.decode(descriptors).file.each { index(it) }
        @entries = @types.filter_map { |name, type| [name, type.descriptor] if map_entry?(type.descriptor) }.to_h
        @roots = rpcs.flat_map { it.last(2) }.uniq.sort
        @reached = reach(@roots)
        @modules = {}
      end

      # @return [Array<Message>] in the order of the descriptors
      def messages = @messages ||= generated(Google::Protobuf::DescriptorProto).map { message(it) }

      # @return [Array<Enum>] in the order of the descriptors
      def enums = @enums ||= generated(Google::Protobuf::EnumDescriptorProto).map { enum(it) }

      # @return [Array<String>] the .proto files holding a generated type
      def files = (messages + enums).map(&:file).uniq.sort

      # @return [Array<Message, Enum>] the generated types +file+ declares outside any message
      def top_level(file) = children.fetch([:file, file], [])

      # @return [Array<Message, Enum>] the generated types the message +full_name+ declares
      def nested(full_name) = children.fetch(full_name, [])

      # @return [Message, Enum] the generated type of that name
      def type(full_name) = by_name.fetch(full_name)

      # @return [Array<String>] the requests and responses of the methods, sorted
      attr_reader :roots

      # @return [String] the package of a type
      def package(full_name) = @types.fetch(full_name).package

      # @param full_name [String] a message or enum, without a leading dot
      # @return [String] the Ruby constant of its value class or module
      def constant(full_name)
        type = @types.fetch(full_name)
        path = full_name.delete_prefix("#{type.package}.").split('.')
        [ROOT, *package_modules(type.package), *path].join('::')
      end

      private

      def index(file)
        file.message_type.each { index_message(it, file, file.package, nil) }
        file.enum_type.each { add(it, file, file.package, nil) }
      end

      def index_message(descriptor, file, package, parent)
        name = add(descriptor, file, package, parent)
        descriptor.nested_type.each { index_message(it, file, package, name) }
        descriptor.enum_type.each { add(it, file, package, name) }
      end

      def add(descriptor, file, package, parent)
        name = [parent || package, descriptor.name].reject(&:empty?).join('.')
        @types[name] = Type.new(descriptor:, file: file.name, package:, parent:)
        name
      end

      # An enum nested in a message needs that message as its namespace, even when no field reaches it.
      def reach(roots)
        queue = roots.dup
        queue.each_with_object({}) do |name, reached|
          next if reached[name] || Shapes::CONVERTED.key?(name)

          reached[name] = true
          type = @types.fetch(name)
          queue << type.parent if type.parent
          queue.concat(referenced(type.descriptor))
        end
      end

      def referenced(descriptor)
        return [] unless descriptor.is_a?(Google::Protobuf::DescriptorProto)

        descriptor.field.filter_map { it.type_name.delete_prefix('.') if %i[TYPE_MESSAGE TYPE_ENUM].include?(it.type) }
      end

      def generated(kind)
        @types.filter_map { |name, type| name if @reached[name] && type.descriptor.is_a?(kind) && !@entries[name] }
      end

      def by_name = @by_name ||= (messages + enums).to_h { [it.full_name, it] }

      def children
        @children ||= @types.select { |name, _| by_name.key?(name) }
                            .group_by { |_, type| type.parent || [:file, type.file] }
                            .transform_values { |types| types.map { by_name.fetch(it.first) } }
      end

      def map_entry?(descriptor) = descriptor.is_a?(Google::Protobuf::DescriptorProto) && descriptor.options&.map_entry

      def message(name)
        descriptor = @types.fetch(name).descriptor
        fields = descriptor.field.map { Shapes.field(it, @entries) }
        oneofs = Shapes.oneofs(descriptor, fields)
        outcome = Shapes.outcome(descriptor)
        Naming.distinct!(name, [*fields.map(&:name), :raw, *oneofs.map(&:reader), *(:problem if outcome)])
        Message.new(full_name: name, constant: constant(name), file: @types.fetch(name).file,
                    fields:, oneofs:, outcome:)
      end

      def enum(name)
        type = @types.fetch(name)
        values = type.descriptor.value.to_a
        Enum.new(full_name: name, constant: constant(name), file: type.file,
                 values: values.map(&:name).zip(Naming.symbols(name, values)))
      end

      def package_modules(package)
        @modules[package] ||=
          if package.empty? || package == 'systems.ajax'
            []
          else
            parent, _, last = package.rpartition('.')
            [*package_modules(parent), module_name(parent, last)]
          end
      end

      # In the app 3.59, hub, third_party_device and z_wave_device have a message of the same name beside them.
      def module_name(parent, segment)
        name = Naming.camelize(segment)
        @types.key?([parent, name].reject(&:empty?).join('.')) ? "#{name}Package" : name
      end
    end
  end
end
