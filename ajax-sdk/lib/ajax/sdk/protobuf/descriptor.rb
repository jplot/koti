# frozen_string_literal: true

module Ajax
  module Sdk
    # The hand-written subset of +descriptor.proto+ and the codec that reads the schemas
    # a {Protobuf::Registry} is built from.
    module Protobuf
      # Builds a {Message} for the hand-written descriptor schema.
      #
      # @api private
      def self.descriptor_message(full_name, fields)
        built = fields.map do |name, number, type, label, type_name|
          Field.new(name:, number:, type:, label:, type_name:, oneof_index: nil, packed: false, proto3_optional: false)
        end
        Message.new(full_name:, fields: built, oneofs: [], map_entry: false)
      end

      # Enough of +descriptor.proto+ to read the FileDescriptorSet that {Registry.from_descriptor_set}
      # loads. Field numbers and types are copied from the standard descriptor; +label+ and +type+ of a
      # FieldDescriptorProto are read as plain int32 since only their numbers matter here. Types: 5 int32,
      # 8 bool, 9 string, 11 message; labels: 1 optional, 3 repeated.
      DESCRIPTOR = Registry.new(
        {
          'google.protobuf.FileDescriptorSet' => descriptor_message(
            'google.protobuf.FileDescriptorSet',
            [[:file, 1, 11, 3, 'google.protobuf.FileDescriptorProto']]
          ),
          'google.protobuf.FileDescriptorProto' => descriptor_message(
            'google.protobuf.FileDescriptorProto',
            [
              [:name, 1, 9, 1, nil], [:package, 2, 9, 1, nil],
              [:message_type, 4, 11, 3, 'google.protobuf.DescriptorProto'],
              [:enum_type, 5, 11, 3, 'google.protobuf.EnumDescriptorProto'],
              [:syntax, 12, 9, 1, nil]
            ]
          ),
          'google.protobuf.DescriptorProto' => descriptor_message(
            'google.protobuf.DescriptorProto',
            [
              [:name, 1, 9, 1, nil],
              [:field, 2, 11, 3, 'google.protobuf.FieldDescriptorProto'],
              [:nested_type, 3, 11, 3, 'google.protobuf.DescriptorProto'],
              [:enum_type, 4, 11, 3, 'google.protobuf.EnumDescriptorProto'],
              [:options, 7, 11, 1, 'google.protobuf.MessageOptions'],
              [:oneof_decl, 8, 11, 3, 'google.protobuf.OneofDescriptorProto']
            ]
          ),
          'google.protobuf.MessageOptions' => descriptor_message(
            'google.protobuf.MessageOptions', [[:map_entry, 7, 8, 1, nil]]
          ),
          'google.protobuf.FieldDescriptorProto' => descriptor_message(
            'google.protobuf.FieldDescriptorProto',
            [
              [:name, 1, 9, 1, nil], [:number, 3, 5, 1, nil], [:label, 4, 5, 1, nil], [:type, 5, 5, 1, nil],
              [:type_name, 6, 9, 1, nil], [:options, 8, 11, 1, 'google.protobuf.FieldOptions'],
              [:oneof_index, 9, 5, 1, nil], [:proto3_optional, 17, 8, 1, nil]
            ]
          ),
          'google.protobuf.FieldOptions' => descriptor_message(
            'google.protobuf.FieldOptions', [[:packed, 2, 8, 1, nil]]
          ),
          'google.protobuf.OneofDescriptorProto' => descriptor_message(
            'google.protobuf.OneofDescriptorProto', [[:name, 1, 9, 1, nil]]
          ),
          'google.protobuf.EnumDescriptorProto' => descriptor_message(
            'google.protobuf.EnumDescriptorProto',
            [[:name, 1, 9, 1, nil], [:value, 2, 11, 3, 'google.protobuf.EnumValueDescriptorProto']]
          ),
          'google.protobuf.EnumValueDescriptorProto' => descriptor_message(
            'google.protobuf.EnumValueDescriptorProto', [[:name, 1, 9, 1, nil], [:number, 2, 5, 1, nil]]
          )
        },
        {}
      )
    end
  end
end
