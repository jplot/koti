# frozen_string_literal: true

module Ajax
  module Sdk
    module Protobuf
      # A single field of a message, as described by a FileDescriptorProto. +type+ and +label+
      # are the integer codes of +descriptor.proto+ (type 11 message, 14 enum; label 3 repeated).
      Field = Data.define(:name, :number, :type, :label, :type_name, :oneof_index, :packed, :proto3_optional)

      # A message type: its fields, its oneof names and whether it is a synthetic map entry.
      Message = Data.define(:full_name, :fields, :oneofs, :map_entry)

      # An enum type: the integer-to-name mapping of its values.
      Enum = Data.define(:full_name, :values)

      # Holds every message and enum known to a client, looked up by fully qualified name.
      class Registry
        # @param messages [Hash{String=>Message}]
        # @param enums [Hash{String=>Enum}]
        # @api private
        def initialize(messages, enums)
          @messages = messages
          @enums = enums
        end

        # @param full_name [String] fully qualified message name, without a leading dot
        # @return [Message]
        # @raise [ArgumentError] when no such message is known
        def message(full_name) = @messages.fetch(full_name) { raise ArgumentError, "unknown message #{full_name}" }

        # @param full_name [String] fully qualified enum name, without a leading dot
        # @return [Enum]
        # @raise [ArgumentError] when no such enum is known
        def enum(full_name) = @enums.fetch(full_name) { raise ArgumentError, "unknown enum #{full_name}" }

        # Builds a registry from a serialized +FileDescriptorSet+, as emitted by
        # +protoc --descriptor_set_out+.
        #
        # @param bytes [String] the serialized FileDescriptorSet
        # @return [Registry]
        def self.from_descriptor_set(bytes)
          set = Codec.new(DESCRIPTOR).decode('google.protobuf.FileDescriptorSet', bytes)
          messages = {} #: Hash[String, Message]
          enums = {} #: Hash[String, Enum]
          list(set[:file]).each { |file| add_file(messages, enums, file) }
          new(messages, enums)
        end

        def self.list(value) = value.nil? ? [] : value

        def self.add_file(messages, enums, file)
          package = file[:package]
          syntax = file[:syntax] || 'proto2'
          list(file[:enum_type]).each { |enum| add_enum(enums, package, enum) }
          list(file[:message_type]).each { |msg| add_message(messages, enums, package, msg, syntax) }
        end

        def self.qualify(package, name) = package.to_s.empty? ? name : "#{package}.#{name}"

        def self.add_enum(enums, scope, descriptor)
          full = qualify(scope, descriptor[:name])
          values = list(descriptor[:value]).to_h { |value| [value[:number] || 0, value[:name].to_sym] }
          enums[full] = Enum.new(full_name: full, values:)
        end

        def self.add_message(messages, enums, scope, descriptor, syntax)
          full = qualify(scope, descriptor[:name])
          messages[full] = build_message(full, descriptor, syntax)
          list(descriptor[:enum_type]).each { |enum| add_enum(enums, full, enum) }
          list(descriptor[:nested_type]).each { |nested| add_message(messages, enums, full, nested, syntax) }
        end

        def self.build_message(full, descriptor, syntax)
          Message.new(
            full_name: full, fields: list(descriptor[:field]).map { |field| build_field(field, syntax) },
            oneofs: list(descriptor[:oneof_decl]).map { it[:name].to_sym },
            map_entry: descriptor.dig(:options, :map_entry) || false
          )
        end

        def self.build_field(descriptor, syntax)
          explicit = descriptor.dig(:options, :packed)
          label = descriptor[:label]
          packed = explicit.nil? ? (syntax == 'proto3' && label == 3 && packable?(descriptor[:type])) : explicit
          Field.new(
            name: descriptor[:name].to_sym, number: descriptor[:number], type: descriptor[:type], label:,
            type_name: descriptor[:type_name]&.delete_prefix('.'), oneof_index: descriptor[:oneof_index],
            packed:, proto3_optional: descriptor[:proto3_optional] || false
          )
        end

        def self.packable?(type) = ![9, 10, 11, 12].include?(type)

        private_class_method :list, :add_file, :qualify, :add_enum, :add_message
        private_class_method :build_message, :build_field, :packable?
      end
    end
  end
end
