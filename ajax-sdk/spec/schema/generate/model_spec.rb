# frozen_string_literal: true

require 'google/protobuf/descriptor_pb'
require_relative '../../../schema/generate/model'

RSpec.describe Schema::Generate::Model do
  def field(name, number, type, **)
    Google::Protobuf::FieldDescriptorProto.new(name:, number:, type:, label: :LABEL_OPTIONAL, **)
  end

  def message(name, *field, **) = Google::Protobuf::DescriptorProto.new(name:, field:, **)

  def enum(name, *values)
    value = values.each_with_index.map { |label, number| Google::Protobuf::EnumValueDescriptorProto.new(name: label, number:) }
    Google::Protobuf::EnumDescriptorProto.new(name:, value:)
  end

  def proto(name, package, **) = Google::Protobuf::FileDescriptorProto.new(name:, package:, syntax: 'proto3', **)

  def model(*file, roots:)
    set = Google::Protobuf::FileDescriptorSet.encode(Google::Protobuf::FileDescriptorSet.new(file:))
    described_class.new(set, roots.map { ["/p.S/m#{it}", 'unary', it, it] })
  end

  def found(model, full_name) = model.messages.find { it.full_name == full_name }

  let(:pkg) { 'systems.ajax.api.x' }

  it 'names a message after its package without systems.ajax' do
    nested = message('Resp', nested_type: [message('Success')])
    model = model(proto('a.proto', "#{pkg}.stream_light_devices", message_type: [nested]),
                  roots: ["#{pkg}.stream_light_devices.Resp"])
    expect(model.constant("#{pkg}.stream_light_devices.Resp.Success"))
      .to eq('Ajax::Sdk::Cloud::Messages::Api::X::StreamLightDevices::Resp::Success')
  end

  it 'suffixes a package module named like a sibling message' do
    model = model(proto('a.proto', "#{pkg}.third_party_device", message_type: [message('Item')]),
                  proto('b.proto', pkg, message_type: [message('ThirdPartyDevice')]),
                  roots: ["#{pkg}.third_party_device.Item", "#{pkg}.ThirdPartyDevice"])
    expect(model.constant("#{pkg}.third_party_device.Item"))
      .to eq('Ajax::Sdk::Cloud::Messages::Api::X::ThirdPartyDevicePackage::Item')
  end

  it 'renames a field named like a Data method' do
    model = model(proto('a.proto', pkg, message_type: [message('M', field('object_id', 1, :TYPE_STRING))]),
                  roots: ["#{pkg}.M"])
    expect(found(model, "#{pkg}.M").fields.map { [it.name, it.key] }).to eq([%i[object_id_ object_id]])
  end

  it 'gives no method to the oneof of an optional field', :aggregate_failures do
    optional = field('opt', 1, :TYPE_INT32, oneof_index: 0, proto3_optional: true)
    m = message('M', optional, oneof_decl: [Google::Protobuf::OneofDescriptorProto.new(name: '_opt')])
    model = model(proto('a.proto', pkg, message_type: [m]), roots: ["#{pkg}.M"])
    expect(found(model, "#{pkg}.M").oneofs).to be_empty
    expect(found(model, "#{pkg}.M").fields.map(&:presence)).to eq([:optional])
  end

  def response(name, problem)
    members = [field('success', 1, :TYPE_MESSAGE, type_name: ".#{pkg}.Ok", oneof_index: 0),
               field(problem, 2, :TYPE_MESSAGE, type_name: ".#{pkg}.Ok", oneof_index: 0)]
    message(name, *members, oneof_decl: [Google::Protobuf::OneofDescriptorProto.new(name: 'result')])
  end

  it 'marks a response whose success and failure share a oneof', :aggregate_failures do
    types = [response('A', 'failure'), response('B', 'error'), message('Ok')]
    model = model(proto('a.proto', pkg, message_type: types), roots: %W[#{pkg}.A #{pkg}.B])
    expect(%w[A B Ok].map { found(model, "#{pkg}.#{it}").outcome }).to eq(['failure', 'error', nil])
    expect(found(model, "#{pkg}.A").oneofs.map { [it.reader, it.choices] }).to eq([[:result, %i[success failure]]])
  end

  def values(*names)
    model = model(proto('a.proto', pkg, message_type: [message('M', field('e', 1, :TYPE_ENUM, type_name: ".#{pkg}.E"))],
                                        enum_type: [enum('E', *names)]), roots: ["#{pkg}.M"])
    model.enums.find { it.full_name == "#{pkg}.E" }.values
  end

  it 'shortens enum values by their common prefix' do
    expect(values('BATTERY_STATE_UNSPECIFIED', 'BATTERY_STATE_OK'))
      .to eq([['BATTERY_STATE_UNSPECIFIED', :unspecified], ['BATTERY_STATE_OK', :ok]])
  end

  it 'keeps a meaningful zero value' do
    expect(values('OWNER', 'ROLE_ADMIN', 'ROLE_USER').map(&:last)).to eq(%i[owner admin user])
  end

  it 'refuses two values with the same short name' do
    expect { values('ON', 'STATE_ON', 'STATE_OFF') }.to raise_error(ArgumentError, /on given twice/)
  end

  def converted_and_map
    entry = message('TagsEntry', field('key', 1, :TYPE_STRING),
                    field('value', 2, :TYPE_MESSAGE, type_name: ".#{pkg}.Sub"),
                    options: Google::Protobuf::MessageOptions.new(map_entry: true))
    message('M', field('at', 1, :TYPE_MESSAGE, type_name: '.google.protobuf.Timestamp'),
            field('w', 2, :TYPE_MESSAGE, type_name: '.google.protobuf.StringValue'),
            field('tags', 3, :TYPE_MESSAGE, type_name: ".#{pkg}.M.TagsEntry", label: :LABEL_REPEATED),
            nested_type: [entry])
  end

  it 'leaves converted types and map entries out', :aggregate_failures do
    model = model(proto('a.proto', pkg, message_type: [converted_and_map, message('Sub')]), roots: ["#{pkg}.M"])
    expect(model.messages.map(&:full_name)).to contain_exactly("#{pkg}.M", "#{pkg}.Sub")
    expect(found(model, "#{pkg}.M").fields.map { [it.kind, it.map&.map(&:type)] })
      .to eq([[:timestamp, nil], [:wrapper, nil], [:message, [:string, "#{pkg}.Sub"]]])
  end

  context 'with the shipped schemas' do
    subject(:shipped) { described_class.load(File.expand_path('../../../lib/ajax/sdk/cloud/schemas', __dir__)) }

    it 'generates every message reachable from the methods' do
      expect(shipped.messages.size).to eq(5828)
    end

    it 'gives every type a distinct constant' do
      constants = (shipped.messages + shipped.enums).map(&:constant)
      expect(constants.uniq.size).to eq(constants.size)
    end
  end
end
