# frozen_string_literal: true

require 'google/protobuf/descriptor_pb'
require_relative '../../../schema/extract/java_literals'

RSpec.describe Schema::Extract::JavaLiterals do
  def java_literal(bytes) = bytes.bytes.map { format('\\u%04x', it) }.join

  it 'reads a descriptor the generated Java builds from a string literal' do
    bytes = Google::Protobuf::FileDescriptorProto.encode(
      Google::Protobuf::FileDescriptorProto.new(name: 'demo.proto', package: 'demo')
    )
    source = %(Descriptor d = internalBuildGeneratedFileFrom(new String[]{"#{java_literal(bytes)}"}, deps);)
    expect(described_class.descriptors(source)).to eq([bytes])
  end

  it 'joins a descriptor split across several literals, a brace in one being a byte' do
    source = %(internalBuildGeneratedFileFrom(new String[]{"\\u0001}\\u0002", "\\u0003"}, x))
    expect(described_class.descriptors(source)).to eq(["\x01}\x02\x03".b])
  end

  it 'reads the unicode and simple escapes jadx writes as ISO-8859-1 bytes' do
    source = %(internalBuildGeneratedFileFrom(new String[]{"\\u00bc\\n\\t\\b\\r\\f\\"\\\\"}, x))
    expect(described_class.descriptors(source)).to eq(["\xBC\n\t\b\r\f\"\\".b])
  end
end
