# frozen_string_literal: true

require 'google/protobuf/descriptor_pb'
require_relative '../../schema/generate/model'

# A proto3 file holding a field of every kind the generator converts, beside the shipped schemas.
module ProbeSchema
  include Google::Protobuf

  module_function

  def field(name, number, type, **) = FieldDescriptorProto.new(name:, number:, type:, label: :LABEL_OPTIONAL, **)

  def message(name, *field, **) = DescriptorProto.new(name:, field:, **)

  def typed(name, number, type_name, **) = field(name, number, :TYPE_MESSAGE, type_name:, **)

  def probe
    message('Probe', field('i', 1, :TYPE_INT64), field('s', 2, :TYPE_STRING),
            field('state', 3, :TYPE_ENUM, type_name: '.probe.State'),
            field('states', 4, :TYPE_ENUM, type_name: '.probe.State', label: :LABEL_REPEATED),
            typed('sub', 5, '.probe.Sub'), typed('subs', 6, '.probe.Sub', label: :LABEL_REPEATED),
            typed('at', 7, '.google.protobuf.Timestamp'), typed('d', 8, '.google.protobuf.Duration'),
            typed('w', 9, '.google.protobuf.StringValue'),
            typed('tags', 10, '.probe.Probe.TagsEntry', label: :LABEL_REPEATED),
            typed('a', 11, '.probe.Sub', oneof_index: 0), field('b', 12, :TYPE_STRING, oneof_index: 0),
            field('opt', 13, :TYPE_INT32, oneof_index: 1, proto3_optional: true),
            nested_type: [tags], oneof_decl: %w[choice _opt].map { OneofDescriptorProto.new(name: it) })
  end

  def tags
    message('TagsEntry', field('key', 1, :TYPE_STRING), typed('value', 2, '.probe.Sub'),
            options: MessageOptions.new(map_entry: true))
  end

  def file
    states = %w[STATE_UNSPECIFIED STATE_ON].each_with_index.map do |name, number|
      EnumValueDescriptorProto.new(name:, number:)
    end
    FileDescriptorProto.new(name: 'probe.proto', package: 'probe', syntax: 'proto3',
                            dependency: %w[google/protobuf/timestamp.proto google/protobuf/duration.proto
                                           google/protobuf/wrappers.proto],
                            message_type: [message('Sub', field('n', 1, :TYPE_INT32)), probe],
                            enum_type: [EnumDescriptorProto.new(name: 'State', value: states)])
  end

  def model
    set = FileDescriptorSet.encode(FileDescriptorSet.new(file: [file]))
    Schema::Generate::Model.new(set, [['/probe.S/m', 'unary', 'probe.Probe', 'probe.Probe']])
  end

  # @return [Class] the google-protobuf class of probe.Probe, in the pool of the shipped schemas
  def message_class
    pool = Ajax::Sdk::Cloud::Schemas.pool
    pool.add_serialized_file(FileDescriptorProto.encode(file)) unless pool.lookup('probe.Probe')
    pool.lookup('probe.Probe').msgclass
  end
end
